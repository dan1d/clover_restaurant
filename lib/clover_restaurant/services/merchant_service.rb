# lib/clover_restaurant/services/merchant_service.rb
module CloverRestaurant
  module Services
    class MerchantService < BaseService
      def get_merchant_info
        logger.info "=== Fetching information for merchant #{@config.merchant_id} ==="

        # Use caching for merchant info as it rarely changes
        @merchant_info ||= make_request(:get, "v3/merchants/#{@config.merchant_id}")
      end

      def get_merchant_properties
        logger.info "=== Fetching properties for merchant #{@config.merchant_id} ==="

        # Use caching for merchant properties as they rarely change
        @merchant_properties ||= make_request(:get, "v3/merchants/#{@config.merchant_id}/properties")
      end

      def get_merchant_property(property_name)
        logger.info "=== Fetching merchant property: #{property_name} ==="

        properties = get_merchant_properties
        return nil unless properties && properties["elements"]

        property = properties["elements"].find { |p| p["name"] == property_name }

        if property
          logger.info "Found property #{property_name} with value: #{property["value"]}"
        else
          logger.info "Property #{property_name} not found"
        end

        property
      end

      def update_merchant_property(property_name, value)
        logger.info "=== Updating merchant property: #{property_name} to #{value} ==="

        # Check if property already has this value
        existing_property = get_merchant_property(property_name)

        if existing_property && existing_property["value"] == value.to_s
          logger.info "Property #{property_name} already has value #{value}, skipping update"
          return existing_property
        end

        # Clear cached properties since we're updating
        @merchant_properties = nil

        payload = {
          "name" => property_name,
          "value" => value
        }

        logger.info "Request payload: #{payload.inspect}"
        make_request(:post, "v3/merchants/#{@config.merchant_id}/properties", payload)
      end

      def get_merchant_gateway_configuration
        logger.info "=== Fetching gateway configuration for merchant #{@config.merchant_id} ==="

        # Use caching for gateway configuration as it rarely changes
        @gateway_configuration ||= make_request(:get, endpoint("gateway_configuration"))
      end

      def get_payment_key
        logger.info "=== Fetching payment key for merchant #{@config.merchant_id} ==="

        # Don't cache payment keys as they may expire or rotate
        make_request(:get, v2_endpoint("pay/key"))
      end

      def get_merchant_devices
        logger.info "=== Fetching devices for merchant #{@config.merchant_id} ==="
        make_request(:get, endpoint("devices"))
      end

      def get_merchant_address
        logger.info "=== Fetching address for merchant #{@config.merchant_id} ==="

        # Use caching for merchant address as it rarely changes
        @merchant_address ||= make_request(:get, endpoint("address"))
      end

      def get_merchant_by_id(merchant_id)
        logger.info "=== Fetching merchant with ID: #{merchant_id} ==="
        make_request(:get, "v3/merchants/#{merchant_id}")
      end

      def get_merchant_metrics(metric_type = "PAYMENTS_VOLUME", time_period = "LAST_7_DAYS")
        logger.info "=== Fetching merchant metrics for #{metric_type} over #{time_period} ==="

        # Validate inputs
        unless %w[PAYMENTS_VOLUME ORDERS_COUNT CUSTOMERS_COUNT].include?(metric_type)
          logger.error "Invalid metric type: #{metric_type}"
          return nil
        end

        unless %w[LAST_7_DAYS LAST_30_DAYS LAST_90_DAYS LAST_YEAR].include?(time_period)
          logger.error "Invalid time period: #{time_period}"
          return nil
        end

        query_params = {
          "metricType" => metric_type,
          "timePeriod" => time_period
        }

        make_request(:get, endpoint("metrics"), nil, query_params)
      end

      def get_merchant_preferences
        logger.info "=== Fetching merchant preferences ==="
        make_request(:get, endpoint("preferences"))
      end

      def update_merchant_preference(preference_name, value)
        logger.info "=== Updating merchant preference: #{preference_name} to #{value} ==="

        payload = {
          "name" => preference_name,
          "value" => value
        }

        make_request(:post, endpoint("preferences"), payload)
      end

      def get_order_types
        logger.info "=== Fetching order types for merchant #{@config.merchant_id} ==="
        make_request(:get, endpoint("order_types"))
      end

      def create_order_type(order_type_data)
        logger.info "=== Creating new order type for merchant #{@config.merchant_id} === "
        logger.info "Order type data: #{order_type_data.inspect}"
        make_request(:post, endpoint("order_types"), order_type_data)
      end

      # Helper method to clear cached data if needed
      def clear_cache
        logger.info "=== Clearing merchant service cache ==="
        @merchant_info = nil
        @merchant_properties = nil
        @gateway_configuration = nil
        @merchant_address = nil
        true
      end
    end
  end
end
