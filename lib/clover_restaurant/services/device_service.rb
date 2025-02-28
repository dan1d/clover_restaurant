module CloverRestaurant
  module Services
    class DeviceService < BaseService
      def get_devices
        logger.info "=== Fetching devices for merchant #{@config.merchant_id} ==="
        response = make_request(:get, endpoint("devices"))

        if response && response["elements"] && !response["elements"].empty?
          logger.info "✅ Retrieved #{response["elements"].size} devices."
          response["elements"]
        else
          logger.warn "❌ No devices found. Using a FAKE device for testing."
          [{ "id" => "FAKE_DEVICE_ID_FOR_TESTING" }] # Fake device ID
        end
      end
    end
  end
end
