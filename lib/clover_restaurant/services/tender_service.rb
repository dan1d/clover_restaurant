require "json"

module CloverRestaurant
  module Services
    class TenderService < BaseService
      TENDER_DATA_PATH = File.expand_path("../data_generation/inventory_data/tenders.json", __dir__)

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

      # ✅ New: Create Standard Tenders
      def create_standard_tenders
        logger.info "🔄 Checking for missing tenders..."

        # ✅ Step 1: Load tenders from JSON
        standard_tenders = load_tenders_json
        existing_tenders = get_tenders.map { |t| t["label"] }

        # ✅ Step 2: Create missing tenders
        missing_tenders = standard_tenders.reject { |t| existing_tenders.include?(t["label"]) }

        if missing_tenders.empty?
          logger.info "✅ All standard tenders already exist. Skipping creation."
          return
        end

        logger.info "🛠 Creating #{missing_tenders.size} missing tenders..."
        missing_tenders.each do |tender_data|
          response = create_tender(tender_data)
          if response && response["id"]
            logger.info "✅ Created tender: #{response["label"]} (ID: #{response["id"]})"
          else
            logger.error "❌ Failed to create tender: #{tender_data["label"]}"
          end
        end
      end

      # ✅ New: Create a Tender via API
      def create_tender(tender_data)
        logger.info "🛠 Creating tender: #{tender_data["label"]}"

        request_body = {
          "label" => tender_data["label"]
        }

        make_request(:post, endpoint("tenders"), request_body)
      end

      # ✅ New: Load JSON Helper
      def load_tenders_json
        return [] unless File.exist?(TENDER_DATA_PATH)

        JSON.parse(File.read(TENDER_DATA_PATH))
      rescue JSON::ParserError => e
        logger.error "❌ Error parsing tenders.json: #{e.message}"
        []
      end
    end
  end
end
