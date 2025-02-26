module CloverRestaurant
  module Services
    class MerchantService < BaseService
      def get_merchant_info
        logger.info "Fetching information for merchant #{@config.merchant_id}"
        make_request(:get, "v3/merchants/#{@config.merchant_id}")
      end

      def get_merchant_properties
        logger.info "Fetching properties for merchant #{@config.merchant_id}"
        make_request(:get, "v3/merchants/#{@config.merchant_id}/properties")
      end

      def update_merchant_property(property_name, value)
        logger.info "Updating merchant property: #{property_name} to #{value}"
        make_request(:post, "v3/merchants/#{@config.merchant_id}/properties", {
                       "name" => property_name,
                       "value" => value
                     })
      end

      def get_merchant_gateway_configuration
        logger.info "Fetching gateway configuration for merchant #{@config.merchant_id}"
        make_request(:get, endpoint("gateway_configuration"))
      end

      def get_payment_key
        logger.info "Fetching payment key for merchant #{@config.merchant_id}"
        make_request(:get, v2_endpoint("pay/key"))
      end

      def get_merchant_devices
        logger.info "Fetching devices for merchant #{@config.merchant_id}"
        make_request(:get, endpoint("devices"))
      end

      def get_merchant_address
        logger.info "Fetching address for merchant #{@config.merchant_id}"
        make_request(:get, endpoint("address"))
      end
    end
  end
end
