# lib/clover_restaurant/services/tender_service.rb
module CloverRestaurant
  module Services
    class TenderService < BaseService
      def get_tenders
        logger.info "=== Fetching tenders for merchant #{@config.merchant_id} ==="
        response = make_request(:get, endpoint("tenders"))

        if response && response["elements"]
          logger.info "✅ Retrieved #{response["elements"].size} tenders."
          response["elements"]
        else
          logger.error "❌ No tenders found or request failed."
          []
        end
      end
    end
  end
end
