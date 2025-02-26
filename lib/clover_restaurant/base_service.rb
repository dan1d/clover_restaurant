module CloverRestaurant
  class BaseService
    attr_reader :config, :logger

    def initialize(custom_config = nil)
      @config = custom_config || CloverRestaurant.configuration
      @config.validate!
      @logger = @config.logger

      # Use API key instead of OAuth token if provided
      if @config.api_key
        @logger.info "=== Using API key for authentication ==="
        @auth_token = @config.api_key
      else
        @logger.info "=== Using OAuth token for authentication ==="
        @auth_token = @config.api_token
      end

      @headers = {
        "Authorization" => "Bearer #{@auth_token}",
        "Content-Type" => "application/json",
        "Accept" => "application/json" # Added this header to match working example
      }

      @logger.info "=== Service initialized with headers: #{@headers.inspect} ==="
      @logger.info "=== Merchant ID: #{@config.merchant_id} ==="
      @logger.info "=== Environment: #{@config.environment} ==="
    end

    def make_request(method, endpoint, payload = nil, query_params = {}, retry_options = {})
      url = "#{@config.environment}#{endpoint.sub(%r{^/}, "")}"

      if query_params && !query_params.empty?
        query_string = query_params.map { |k, v| "#{k}=#{URI.encode_www_form_component(v.to_s)}" }.join("&")
        url = "#{url}?#{query_string}"
      end

      logger.info "======== REQUEST ========"
      logger.info "METHOD: #{method.upcase}"
      logger.info "URL: #{url}"
      logger.info "HEADERS: #{@headers.inspect}"

      if payload && method != :get
        logger.info "PAYLOAD: #{payload.inspect}"
        logger.info "PAYLOAD JSON: #{payload.to_json}"
      end

      response = nil
      start_time = Time.now

      begin
        response = case method
                   when :get
                     HTTParty.get(url, headers: @headers)
                   when :post
                     HTTParty.post(url, headers: @headers, body: payload.to_json)
                   when :put
                     HTTParty.put(url, headers: @headers, body: payload.to_json)
                   when :delete
                     HTTParty.delete(url, headers: @headers)
                   else
                     raise "Unsupported HTTP method: #{method}"
                   end
      rescue StandardError => e
        logger.error "EXCEPTION DURING HTTP REQUEST: #{e.class.name}: #{e.message}"
        raise ServiceError, "HTTP request failed: #{e.message}"
      end

      end_time = Time.now

      logger.info "======== RESPONSE ========"
      logger.info "TIME: #{(end_time - start_time) * 1000} ms"
      logger.info "STATUS: #{response.code}"
      logger.info "BODY: #{response.body ? response.body[0..500] : "<empty>"}"

      # Check for error status and handle appropriately
      case response.code
      when 200..299
        # Success! Parse JSON or return true
        return true unless response.body && !response.body.empty?

        begin
          JSON.parse(response.body)
        rescue JSON::ParserError => e
          logger.error "JSON parsing error: #{e.message}"
          raise APIError, "JSON parsing error: #{e.message}"
        end

      # For successful empty responses (like 204 No Content)

      when 405
        # Method Not Allowed - This is the error we're specifically trying to handle
        logger.error "METHOD NOT ALLOWED ERROR (405): #{response.body}"

        # Check if we should try alternative approaches
        if retry_options[:alternative_method]
          logger.info "Trying alternative method: #{retry_options[:alternative_method].upcase}"
          make_request(retry_options[:alternative_method], endpoint, payload, query_params)
        elsif retry_options[:alternative_endpoint]
          logger.info "Trying alternative endpoint: #{retry_options[:alternative_endpoint]}"
          make_request(method, retry_options[:alternative_endpoint], payload, query_params)
        else
          # No alternatives specified, raise the error
          raise APIError, "Method not allowed (405): #{response.body}"
        end
      when 401
        logger.error "AUTHENTICATION FAILED: #{response.body}"
        raise AuthenticationError, "Authentication failed: #{response.body}"
      when 404
        logger.error "RESOURCE NOT FOUND: #{response.body}"
        raise ResourceNotFoundError, "Resource not found: #{response.body}"
      when 429
        logger.error "RATE LIMIT EXCEEDED: #{response.body}"
        raise RateLimitError, "Rate limit exceeded: #{response.body}"
      else
        logger.error "REQUEST FAILED (#{response.code}): #{response.body}"
        raise APIError, "Request failed with status #{response.code}: #{response.body}"
      end
    rescue StandardError => e
      logger.error "REQUEST ERROR: #{e.message}"
      logger.error e.backtrace.join("\n")
      raise ServiceError, "Request error: #{e.message}"
    end

    def endpoint(path)
      path_str = "v3/merchants/#{@config.merchant_id}/#{path.sub(%r{^/}, "")}"
      logger.debug "Generated endpoint: #{path_str}"
      path_str
    end

    def v2_endpoint(path)
      path_str = "v2/merchant/#{@config.merchant_id}/#{path.sub(%r{^/}, "")}"
      logger.debug "Generated v2 endpoint: #{path_str}"
      path_str
    end

    # Helper method to make the most appropriate request for a given action
    def smart_request(action, resource_type, resource_id = nil, data = nil, query_params = {})
      logger.info "Making smart request: action=#{action}, resource=#{resource_type}, id=#{resource_id}"

      # Map of resource types to their API endpoints
      endpoints = {
        "modifier_groups" => "modifier_groups",
        "modifiers" => "modifiers",
        "items" => "items",
        "categories" => "categories"
        # Add other resources as needed
      }

      # Get the base endpoint for this resource type
      base_endpoint = endpoints[resource_type] || resource_type

      # Build the endpoint based on the action and resource
      case action
      when :list
        make_request(:get, endpoint(base_endpoint), nil, query_params)
      when :get
        raise "Resource ID required for :get action" unless resource_id

        make_request(:get, endpoint("#{base_endpoint}/#{resource_id}"), nil, query_params)
      when :create
        raise "Data required for :create action" unless data

        # Try the standard endpoint first
        begin
          make_request(:post, endpoint(base_endpoint), data, query_params)
        rescue APIError => e
          raise e unless e.message.include?("405")
          # For modifiers, try the alternative endpoint through the modifier group
          raise e unless resource_type == "modifiers" && data["modifierGroup"] && data["modifierGroup"]["id"]

          group_id = data["modifierGroup"]["id"]
          logger.info "Got 405 error, trying alternative endpoint for modifier creation"
          make_request(:post, endpoint("modifier_groups/#{group_id}/modifiers"), data, query_params)

          # Can't use an alternative endpoint, re-raise the error

          # Not a 405 error, re-raise it
        end
      when :update
        raise "Resource ID required for :update action" unless resource_id
        raise "Data required for :update action" unless data

        make_request(:post, endpoint("#{base_endpoint}/#{resource_id}"), data, query_params)
      when :delete
        raise "Resource ID required for :delete action" unless resource_id

        make_request(:delete, endpoint("#{base_endpoint}/#{resource_id}"), nil, query_params)
      when :associate
        # For adding one resource to another (e.g., adding a modifier group to an item)
        raise "Resource ID required for :associate action" unless resource_id
        raise "Data required for :associate action" unless data
        raise "Target resource type required in data" unless data["target_type"]
        raise "Target ID required in data" unless data["target_id"]

        target_type = data.delete("target_type")
        target_id = data.delete("target_id")

        make_request(:post, endpoint("#{base_endpoint}/#{resource_id}/#{target_type}"),
                     { target_type.sub(/s$/, "") => { "id" => target_id } }, query_params)
      else
        raise "Unsupported action: #{action}"
      end
    end
  end
end
