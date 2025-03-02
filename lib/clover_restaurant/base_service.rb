require_relative "vcr_setup"

module CloverRestaurant
  class BaseService
    attr_reader :config, :logger

    def initialize(custom_config = nil)
      @config = custom_config || CloverRestaurant.configuration
      @services_manager = CloverRestaurant::CloverServicesManager.new
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
        "Accept" => "application/json"
      }

      @logger.info "=== Service initialized with headers: #{@headers.inspect} ==="
      @logger.info "=== Merchant ID: #{@config.merchant_id} ==="
      @logger.info "=== Environment: #{@config.environment} ==="
    end

    def make_request(method, endpoint, payload = nil, query_params = {}, retry_options = {})
      url = "#{@config.environment}#{endpoint.sub(%r{^/}, "")}"

      # Append query params if provided
      if query_params && !query_params.empty?
        query_string = query_params.map { |k, v| "#{k}=#{URI.encode_www_form_component(v.to_s)}" }.join("&")
        url = "#{url}?#{query_string}"
      end

      # Generate a unique cache key for this request
      cassette_name = generate_cassette_name(method, url, payload)
      puts "PAYLOAD: #{payload}"
      # logger.info "Using VCR Cassette: #{cassette_name}"

      # response = VCR.use_cassette(cassette_name) do
      response = send_http_request(method, url, payload)
      # end

      handle_response(response)
    end

    def endpoint(path)
      "v3/merchants/#{@config.merchant_id}/#{path.sub(%r{^/}, "")}"
    end

    def v2_endpoint(path)
      "v2/merchant/#{@config.merchant_id}/#{path.sub(%r{^/}, "")}"
    end

    private

    def send_http_request(method, url, payload)
      logger.info "======== REQUEST ========"
      logger.info "METHOD: #{method.upcase}"
      logger.info "URL: #{url}"
      logger.info "HEADERS: #{@headers.inspect}"

      if payload && method != :get
        logger.info "PAYLOAD: #{payload.inspect}"
        logger.info "PAYLOAD JSON: #{payload.to_json}"
      end

      start_time = Time.now

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

      end_time = Time.now

      logger.info "======== RESPONSE ========"
      logger.info "TIME: #{(end_time - start_time) * 1000} ms"
      logger.info "STATUS: #{response.code}"
      logger.info "BODY: #{response.body ? response.body[0..500] : "<empty>"}"

      response
    rescue StandardError => e
      logger.error "EXCEPTION DURING HTTP REQUEST: #{e.class.name}: #{e.message}"
      raise ServiceError, "HTTP request failed: #{e.message}"
    end

    def handle_response(response)
      case response.code
      when 200..299
        return true unless response.body && !response.body.empty?

        begin
          JSON.parse(response.body)
        rescue JSON::ParserError => e
          logger.error "JSON parsing error: #{e.message}"
          raise APIError, "JSON parsing error: #{e.message}"
        end
      when 405
        logger.error "METHOD NOT ALLOWED ERROR (405): #{response.body}"
        raise APIError, "Method not allowed (405): #{response.body}"
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
    end

    def generate_cassette_name(method, url, payload)
      payload_hash = payload.nil? ? "" : Digest::SHA256.hexdigest(payload.to_json)
      "#{method}_#{Digest::SHA256.hexdigest(url)}_#{payload_hash}"
    end

    # Clears the VCR cache
    def clear_cached_requests
      FileUtils.rm_rf("tmp/vcr_cassettes")
      logger.info "Cache cleared!"
    end
  end
end
