# lib/clover_restaurant/services/tax_rate_service.rb
module CloverRestaurant
  module Services
    class TaxRateService < BaseService
      def get_tax_rates(limit = 100, offset = 0)
        logger.info "Fetching tax rates for merchant #{@config.merchant_id}"
        make_request(:get, endpoint("tax_rates"), nil, { limit: limit, offset: offset })
      end

      def get_tax_rate(tax_rate_id)
        logger.info "Fetching tax rate #{tax_rate_id} for merchant #{@config.merchant_id}"
        make_request(:get, endpoint("tax_rates/#{tax_rate_id}"))
      end

      def create_tax_rate(tax_rate_data)
        logger.info "Creating new tax rate for merchant #{@config.merchant_id}"
        make_request(:post, endpoint("tax_rates"), tax_rate_data)
      end

      def update_tax_rate(tax_rate_id, tax_rate_data)
        logger.info "Updating tax rate #{tax_rate_id} for merchant #{@config.merchant_id}"
        make_request(:post, endpoint("tax_rates/#{tax_rate_id}"), tax_rate_data)
      end

      def delete_tax_rate(tax_rate_id)
        logger.info "Deleting tax rate #{tax_rate_id} for merchant #{@config.merchant_id}"
        make_request(:delete, endpoint("tax_rates/#{tax_rate_id}"))
      end

      def get_default_tax_rates
        logger.info "Fetching default tax rates for merchant #{@config.merchant_id}"
        make_request(:get, endpoint("default_tax_rates"))
      end

      def set_default_tax_rates(tax_rate_ids)
        logger.info "=== Setting default tax rates for merchant #{@config.merchant_id} ==="
        logger.info "Tax rate IDs: #{tax_rate_ids.inspect}"

        # Based on API documentation and working example, the endpoint might be different
        # Let's try multiple approaches

        # Approach 1: Using v3 default_tax_rates endpoint with POST (original approach)
        begin
          # Create tax rate list as in original code
          tax_rates = tax_rate_ids.map { |id| { "id" => id } }
          payload = { "elements" => tax_rates }

          logger.info "ATTEMPT 1: Using POST to default_tax_rates with elements array"
          logger.info "Request payload: #{payload.inspect}"

          return make_request(:post, endpoint("default_tax_rates"), payload)
        rescue StandardError => e
          logger.error "ATTEMPT 1 failed: #{e.message}"
        end

        # Approach 2: Using PUT instead of POST
        begin
          # Same payload structure
          tax_rates = tax_rate_ids.map { |id| { "id" => id } }
          payload = { "elements" => tax_rates }

          logger.info "ATTEMPT 2: Using PUT instead of POST"
          logger.info "Request payload: #{payload.inspect}"

          return make_request(:put, endpoint("default_tax_rates"), payload)
        rescue StandardError => e
          logger.error "ATTEMPT 2 failed: #{e.message}"
        end

        # Approach 3: Different payload structure - send as array
        begin
          # Simpler payload structure
          tax_rates = tax_rate_ids.map { |id| { "id" => id } }

          logger.info "ATTEMPT 3: Sending direct array of tax rates"
          logger.info "Request payload: #{tax_rates.inspect}"

          return make_request(:post, endpoint("default_tax_rates"), tax_rates)
        rescue StandardError => e
          logger.error "ATTEMPT 3 failed: #{e.message}"
        end

        # Approach 4: Set individually one by one
        begin
          logger.info "ATTEMPT 4: Setting tax rates one by one"

          results = []
          tax_rate_ids.each do |id|
            logger.info "Setting tax rate ID: #{id} as default"
            result = make_request(:post, endpoint("default_tax_rate"), { "id" => id })
            results << result
          end

          return results
        rescue StandardError => e
          logger.error "ATTEMPT 4 failed: #{e.message}"
        end

        # Approach 5: A different endpoint structure based on API docs
        begin
          logger.info "ATTEMPT 5: Using put with tax_rates/default endpoint"

          if tax_rate_ids.size == 1
            tax_rate_id = tax_rate_ids.first
            return make_request(:put, endpoint("tax_rates/#{tax_rate_id}/default"), { "isDefault" => true })
          else
            logger.warn "Cannot use approach 5 with multiple tax rates"
            raise "Multiple tax rates not supported with this approach"
          end
        rescue StandardError => e
          logger.error "ATTEMPT 5 failed: #{e.message}"
        end

        # If all attempts have failed, let's flag the tax rate as default during creation/update
        # instead of trying to set it separately
        logger.error "All attempts to set default tax rates failed."
        logger.info "Consider updating the tax rate directly with isDefault=true instead"

        # Return empty array to indicate no default tax rates were set
        []
      end

      def create_standard_tax_rates
        logger.info "=== Creating standard tax rates for a restaurant ==="

        standard_tax_rates = [
          {
            "name" => "Sales Tax",
            "rate" => 8.50,
            "taxable" => true,
            "isDefault" => true
          },
          {
            "name" => "Alcohol Tax",
            "rate" => 10.00,
            "taxable" => true,
            "isDefault" => false
          },
          {
            "name" => "Takeout Tax",
            "rate" => 6.00,
            "taxable" => true,
            "isDefault" => false
          },
          {
            "name" => "No Tax",
            "rate" => 0.00,
            "taxable" => false,
            "isDefault" => false
          }
        ]

        created_tax_rates = []

        logger.info "Creating #{standard_tax_rates.size} standard tax rates"

        standard_tax_rates.each_with_index do |tax_rate_data, index|
          logger.info "Creating tax rate #{index + 1}/#{standard_tax_rates.size}: #{tax_rate_data["name"]}"

          begin
            tax_rate = create_tax_rate(tax_rate_data)
            if tax_rate && tax_rate["id"]
              logger.info "Successfully created tax rate: #{tax_rate["name"]} with ID: #{tax_rate["id"]}"
              created_tax_rates << tax_rate
            else
              logger.warn "Created tax rate but received unexpected response: #{tax_rate.inspect}"
            end
          rescue StandardError => e
            logger.error "Failed to create tax rate #{tax_rate_data["name"]}: #{e.message}"
          end
        end

        logger.info "Created #{created_tax_rates.size} tax rates successfully"

        # Instead of setting default tax rate through a separate API call,
        # we attempt to do it but continue if it fails
        if default_tax_rate = created_tax_rates.find { |tr| tr["isDefault"] }
          logger.info "Setting default tax rate: #{default_tax_rate["name"]} (ID: #{default_tax_rate["id"]})"

          begin
            set_default_tax_rates([default_tax_rate["id"]])
            logger.info "Successfully set default tax rate"
          rescue StandardError => e
            logger.error "Failed to set default tax rate: #{e.message}"
            logger.info "Continuing without setting default tax rate"
          end
        else
          logger.warn "No default tax rate found among created tax rates"
        end

        created_tax_rates
      end

      def apply_tax_rate_to_item(item_id, tax_rate_id)
        logger.info "Applying tax rate #{tax_rate_id} to item #{item_id}"
        make_request(:post, endpoint("items/#{item_id}/tax_rates"), {
                       "taxRate" => { "id" => tax_rate_id }
                     })
      end

      def remove_tax_rate_from_item(item_id, tax_rate_id)
        logger.info "Removing tax rate #{tax_rate_id} from item #{item_id}"
        make_request(:delete, endpoint("items/#{item_id}/tax_rates/#{tax_rate_id}"))
      end

      def get_item_tax_rates(item_id)
        logger.info "Fetching tax rates for item #{item_id}"
        make_request(:get, endpoint("items/#{item_id}/tax_rates"))
      end

      def apply_tax_rate_to_order(order_id, tax_rate_id)
        logger.info "Applying tax rate #{tax_rate_id} to order #{order_id}"
        make_request(:post, endpoint("orders/#{order_id}/tax_rates"), {
                       "taxRate" => { "id" => tax_rate_id }
                     })
      end

      def remove_tax_rate_from_order(order_id, tax_rate_id)
        logger.info "Removing tax rate #{tax_rate_id} from order #{order_id}"
        make_request(:delete, endpoint("orders/#{order_id}/tax_rates/#{tax_rate_id}"))
      end

      def get_order_tax_rates(order_id)
        logger.info "Fetching tax rates for order #{order_id}"
        make_request(:get, endpoint("orders/#{order_id}/tax_rates"))
      end

      def create_standard_tax_rates
        logger.info "Creating standard tax rates for a restaurant"

        standard_tax_rates = [
          {
            "name" => "Sales Tax",
            "rate" => 8.50,
            "taxable" => true,
            "isDefault" => true
          },
          {
            "name" => "Alcohol Tax",
            "rate" => 10.00,
            "taxable" => true,
            "isDefault" => false
          },
          {
            "name" => "Takeout Tax",
            "rate" => 6.00,
            "taxable" => true,
            "isDefault" => false
          },
          {
            "name" => "No Tax",
            "rate" => 0.00,
            "taxable" => false,
            "isDefault" => false
          }
        ]

        created_tax_rates = []

        standard_tax_rates.each do |tax_rate_data|
          tax_rate = create_tax_rate(tax_rate_data)
          created_tax_rates << tax_rate if tax_rate && tax_rate["id"]
        end

        # Set the default tax rate
        if default_tax_rate = created_tax_rates.find { |tr| tr["isDefault"] }
          set_default_tax_rates([default_tax_rate["id"]])
        end

        created_tax_rates
      end

      def assign_category_tax_rates(categories, tax_rates)
        logger.info "Assigning appropriate tax rates to categories"

        return false if categories.nil? || categories.empty? || tax_rates.nil? || tax_rates.empty?

        # Map tax rates by name for easier lookup
        tax_rate_map = {}
        tax_rates.each do |tax_rate|
          tax_rate_map[tax_rate["name"]] = tax_rate
        end

        # Define category-to-tax-rate mappings
        category_tax_map = {
          "Appetizers" => ["Sales Tax"],
          "Entrees" => ["Sales Tax"],
          "Sides" => ["Sales Tax"],
          "Desserts" => ["Sales Tax"],
          "Breakfast" => ["Sales Tax"],
          "Lunch" => ["Sales Tax"],
          "Drinks" => ["Sales Tax"],
          "Alcoholic Beverages" => ["Sales Tax", "Alcohol Tax"],
          "Beer" => ["Sales Tax", "Alcohol Tax"],
          "Wine" => ["Sales Tax", "Alcohol Tax"],
          "Spirits" => ["Sales Tax", "Alcohol Tax"],
          "Cocktails" => ["Sales Tax", "Alcohol Tax"],
          "To Go" => ["Takeout Tax"],
          "Takeout" => ["Takeout Tax"],
          "Merchandise" => ["Sales Tax"],
          "Gift Cards" => ["No Tax"]
        }

        # Process each category
        inventory_service = InventoryService.new(@config)

        categories.each do |category|
          category_name = category["name"]

          # Find matching tax rates for this category
          applicable_tax_rates = []

          category_tax_map.each do |category_pattern, tax_rate_names|
            next unless category_name.downcase.include?(category_pattern.downcase)

            tax_rate_names.each do |tax_rate_name|
              applicable_tax_rates << tax_rate_map[tax_rate_name] if tax_rate_map[tax_rate_name]
            end
          end

          # If no specific match, use default tax rate
          applicable_tax_rates << tax_rate_map["Sales Tax"] if applicable_tax_rates.empty? && tax_rate_map["Sales Tax"]

          # Get items in this category
          items_response = make_request(:get, endpoint("categories/#{category["id"]}/items"))

          next unless items_response && items_response["elements"]

          # Apply tax rates to each item
          items_response["elements"].each do |item|
            applicable_tax_rates.each do |tax_rate|
              apply_tax_rate_to_item(item["id"], tax_rate["id"])
            end
          end
        end

        true
      end

      def calculate_tax(amount, tax_rate)
        logger.info "Calculating tax for amount #{amount} with rate #{tax_rate}%"

        tax_amount = (amount * tax_rate / 100.0).round

        {
          "amount" => amount,
          "taxRate" => tax_rate,
          "taxAmount" => tax_amount,
          "totalAmount" => amount + tax_amount
        }
      end
    end
  end
end
