module CloverRestaurant
  module Services
    class BaseService
      attr_reader :config, :logger

      def initialize(config = nil)
        @config = config || CloverRestaurant.config
        @logger = @config.logger
        @state = StateManager.new

        logger.info "=== Using OAuth token for authentication ==="
        logger.info "=== Service initialized with headers: #{headers.inspect} ==="
        logger.info "=== Merchant ID: #{@config.merchant_id} ==="
        logger.info "=== Environment: #{@config.environment} ==="
      end

      protected

      def make_request(method, url, payload = nil, query_params = nil)
        # Check if this exact request has been made before
        cache_key = generate_cache_key(method, url, payload)
        cached_response = @state.get_step_data(cache_key)

        if cached_response && !force_request?(method)
          logger.info "Using cached response for #{method} #{url}"
          return cached_response
        end

        full_url = build_url(url, query_params)

        logger.info "======== REQUEST ========"
        logger.info "METHOD: #{method.to_s.upcase}"
        logger.info "URL: #{full_url}"
        logger.info "HEADERS: #{headers}"

        if payload
          logger.info "PAYLOAD: #{payload.inspect}"
          logger.info "PAYLOAD JSON: #{payload.to_json}"
        end

        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        response = case method
                  when :get
                    RestClient.get(full_url, headers)
                  when :post
                    RestClient.post(full_url, payload.to_json, headers)
                  when :put
                    RestClient.put(full_url, payload.to_json, headers)
                  when :delete
                    RestClient.delete(full_url, headers)
                  else
                    raise "Unsupported HTTP method: #{method}"
                  end

        end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        duration = (end_time - start_time) * 1000 # Convert to milliseconds

        logger.info "======== RESPONSE ========"
        logger.info "TIME: #{duration} ms"
        logger.info "STATUS: #{response.code}"
        logger.info "BODY: #{response.body}"

        parsed_response = handle_response(response)

        # Cache successful responses for idempotent methods
        if response.code.between?(200, 299) && !force_request?(method)
          @state.mark_step_completed(cache_key, parsed_response)
        end

        parsed_response
      rescue RestClient::Exception => e
        logger.error "REQUEST FAILED (#{e.http_code}): #{e.response.body}"
        handle_error(e)
      end

      def endpoint(path)
        "v3/merchants/#{@config.merchant_id}/#{path}"
      end

      private

      def headers
        {
          'Authorization' => "Bearer #{@config.oauth_token}",
          'Content-Type' => 'application/json',
          'Accept' => 'application/json'
        }
      end

      def build_url(url, query_params = nil)
        full_url = url.start_with?('http') ? url : "#{@config.environment}#{url}"
        return full_url unless query_params

        uri = URI(full_url)
        uri.query = URI.encode_www_form(query_params)
        uri.to_s
      end

      def handle_response(response)
        return nil if response.body.empty?

        begin
          JSON.parse(response.body)
        rescue JSON::ParserError => e
          logger.error "Failed to parse response: #{e.message}"
          raise "Invalid JSON response: #{response.body}"
        end
      end

      def handle_error(error)
        error_response = begin
          JSON.parse(error.response.body)
        rescue
          { "message" => error.response.body }
        end

        raise "Request failed with status #{error.http_code}: #{error_response.to_json}"
      end

      def generate_cache_key(method, url, payload)
        components = [
          method.to_s.upcase,
          url.gsub(/[^a-zA-Z0-9]/, '_'),
          payload ? Digest::MD5.hexdigest(payload.to_json) : 'no_payload'
        ]
        components.join('_')
      end

      def force_request?(method)
        # Never cache DELETE requests or force-refresh flags
        method == :delete || @config.force_refresh
      end
    end
  end
end
