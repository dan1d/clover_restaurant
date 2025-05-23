module CloverRestaurant
  module Services
    class BaseService
      attr_reader :config, :logger

      def initialize(config = nil)
        @config = config || CloverRestaurant.config
        @logger = @config.logger
        @state = StateManager.new(@config.db_path || 'clover_state.db', @logger)

        logger.info "=== Using OAuth token for authentication ==="
        logger.info "=== Service initialized with headers: #{headers.inspect} ==="
        logger.info "=== Merchant ID: #{@config.merchant_id} ==="
        logger.info "=== Environment: #{@config.environment} ==="
      end

      protected

      def make_request(method, url, payload = nil, query_params = nil)
        @logger.info "MR_PRE_GK: method=#{method}, url=#{url}, payload_present=#{!payload.nil?}, query_params_class=#{query_params.class}, query_params_nil=#{query_params.nil?}, query_params_empty=#{query_params&.empty?}"
        @logger.info "MR_PRE_GK_QP_INSPECT: #{query_params.inspect}"

        # Check if this exact request has been made before
        # cache_key = generate_cache_key(method, url, payload, query_params) # DISABLED CACHING
        # @logger.info "MR_POST_GK: cache_key_in_mr = '#{cache_key}'" # DISABLED CACHING

        # cached_response = @state.get_step_data(cache_key) # DISABLED CACHING

        # if cached_response && !force_request?(method) # DISABLED CACHING
        #   logger.info "Using cached response for #{method} #{url}" # DISABLED CACHING
        #   return cached_response # DISABLED CACHING
        # end # DISABLED CACHING
        logger.info "CACHE DISABLED: Bypassing cache lookup for #{method} #{url}"

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

        # Cache successful responses for idempotent methods or if not a mutating method
        # if response.code.between?(200, 299) # DISABLED CACHING
        #   if [:get, :head, :options].include?(method.downcase) && !force_request?(method) # Only cache safe, idempotent methods # DISABLED CACHING
        #     @state.mark_step_completed(cache_key, parsed_response) # DISABLED CACHING
        #   elsif [:post, :put, :delete].include?(method.downcase) # DISABLED CACHING
        #     # If a mutating request was successful, clear relevant GET caches for that URL path # DISABLED CACHING
        #     @logger.info "BS_CLEAR_CACHE: Attempting to clear cache for URL: '#{url}' after #{method.to_s.upcase} request." # DISABLED CACHING
        #     @state.clear_cache_for_url_path(url) # url is the base path without query params # DISABLED CACHING
        #   end # DISABLED CACHING
        # end # DISABLED CACHING
        logger.info "CACHE DISABLED: Bypassing cache write and invalidation for #{method} #{url}"

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

      def generate_cache_key(method, url, payload, query_params = nil)
        # Sanitize URL to be FS-friendly and consistent
        sane_url = url.gsub(%r{[^a-zA-Z0-9_/.-]}, '_') # Allow basic path chars

        @logger.info "GK_ENTRY: method=#{method}, url=#{url}, payload_present=#{!payload.nil?}, query_params_class=#{query_params.class}, query_params_nil=#{query_params.nil?}, query_params_empty=#{query_params&.empty?}"
        @logger.info "GK_QP_INSPECT: #{query_params.inspect}"
        @logger.info "CACHE DISABLED: generate_cache_key called but result will not be used."

        components = [
          method.to_s.upcase,
          sane_url
        ]

        is_get = (method == :get)
        has_query_params = !!query_params
        query_params_not_empty = query_params && !query_params.empty? # Ensure query_params is not nil before calling .empty?

        @logger.info "GK_COND_CHECK: is_get=#{is_get}, has_query_params=#{has_query_params}, query_params_not_empty=#{query_params_not_empty}"

        if is_get && has_query_params && query_params_not_empty
          @logger.info "GK_BRANCH: GET with query_params"
          # Sort query params for consistent key order
          sorted_query_string = URI.encode_www_form(query_params.sort_by { |k, _| k.to_s })
          components << Digest::MD5.hexdigest(sorted_query_string)
        elsif payload # For POST, PUT etc.
          @logger.info "GK_BRANCH: Payload present (POST/PUT)"
          components << Digest::MD5.hexdigest(payload.to_json)
        else
          @logger.info "GK_BRANCH: Fallback (GET no query, DELETE, etc.)"
          components << 'no_payload_or_query' # For GET without query, or other methods without payload
        end

        key = components.join('_')
        @logger.info "CACHE_KEY_GEN: Generated cache key: #{key} for method: #{method}, url: #{url}, query_params: #{query_params.inspect}"
        key
      end

      def force_request?(method)
        # Never cache DELETE requests or force-refresh flags
        # We cache GET, HEAD, OPTIONS. We don't cache POST, PUT, DELETE.
        # force_request? should determine if we *bypass* a read from cache for GET/HEAD/OPTIONS.
        # Mutating methods (POST, PUT, DELETE) should always make a request and not read from cache.
        # ![:get, :head, :options].include?(method.downcase) || @config.force_refresh # ORIGINAL LOGIC
        @logger.info "CACHE DISABLED: force_request? will always return true."
        true # CACHE DISABLED: Always force request
      end
    end
  end
end
