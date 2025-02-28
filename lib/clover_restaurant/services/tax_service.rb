# lib/clover_restaurant/services/tax_rate_service.rb
module CloverRestaurant
  module Services
    class TaxService < BaseService
      def get_tax_rates(limit = 100, offset = 0)
        logger.info "=== Fetching tax rates for merchant #{@config.merchant_id} ==="
        response = make_request(:get, endpoint("tax_rates"), nil, { limit: limit, offset: offset })

        if response && response["elements"]
          logger.info "✅ Successfully fetched #{response["elements"].size} tax rates."
        else
          logger.warn "⚠️ WARNING: No tax rates found or API response is empty!"
        end

        response
      end

      def get_tax_rate(tax_rate_id)
        logger.info "=== Fetching tax rate #{tax_rate_id} for merchant #{@config.merchant_id} ==="
        make_request(:get, endpoint("tax_rates/#{tax_rate_id}"))
      end

      def create_tax_rate(tax_rate_data)
        logger.info "=== Creating new tax rate for merchant #{@config.merchant_id} ==="

        # Check if a tax rate with this name already exists
        existing_rates = get_tax_rates
        if existing_rates && existing_rates["elements"]
          existing_rate = existing_rates["elements"].find { |r| r["name"] == tax_rate_data["name"] }
          if existing_rate
            logger.info "Tax rate '#{tax_rate_data["name"]}' already exists with ID: #{existing_rate["id"]}, skipping creation"
            return existing_rate
          end
        end

        logger.info "Tax rate data: #{tax_rate_data.inspect}"
        make_request(:post, endpoint("tax_rates"), tax_rate_data)
      end

      def update_tax_rate(tax_rate_id, tax_rate_data)
        logger.info "=== Updating tax rate #{tax_rate_id} for merchant #{@config.merchant_id} ==="
        logger.info "Update data: #{tax_rate_data.inspect}"
        make_request(:post, endpoint("tax_rates/#{tax_rate_id}"), tax_rate_data)
      end

      def delete_tax_rate(tax_rate_id)
        logger.info "=== Deleting tax rate #{tax_rate_id} for merchant #{@config.merchant_id} ==="
        make_request(:delete, endpoint("tax_rates/#{tax_rate_id}"))
      end

      def get_default_tax_rates
        logger.info "=== Fetching default tax rates for merchant #{@config.merchant_id} ==="
        make_request(:get, endpoint("default_tax_rates"))
      end

      def set_default_tax_rates(tax_rate_ids)
        logger.info "=== Setting default tax rates for merchant #{@config.merchant_id} ==="
        logger.info "Tax rate IDs: #{tax_rate_ids.inspect}"

        # Check if the tax rate is already set as default
        default_rates = get_default_tax_rates
        if default_rates && default_rates["elements"] &&
           default_rates["elements"].any? { |dr| tax_rate_ids.include?(dr["id"]) }
          logger.info "Tax rate is already set as default, skipping update"
          return default_rates
        end

        # Try multiple approaches with progressive fallback for VCR compatibility

        # Approach 1: Using v3 default_tax_rates endpoint with POST
        begin
          # Create tax rate list
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

        # Approach 3: Try updating the tax rate directly with isDefault=true
        begin
          logger.info "ATTEMPT 3: Updating tax rate directly with isDefault=true"

          results = []
          tax_rate_ids.each do |id|
            tax_rate = get_tax_rate(id)
            next unless tax_rate

            tax_rate["isDefault"] = true
            result = update_tax_rate(id, { "isDefault" => true })
            results << result if result
          end

          return results.empty? ? nil : results
        rescue StandardError => e
          logger.error "ATTEMPT 3 failed: #{e.message}"
        end

        logger.error "All attempts to set default tax rates failed"
        nil
      end

      def apply_tax_rate_to_item(item_id, tax_rate_id)
        logger.info "=== Applying tax rate #{tax_rate_id} to item #{item_id} ==="

        # Check if this tax rate is already applied to the item
        item_tax_rates = get_item_tax_rates(item_id)
        if item_tax_rates && item_tax_rates["elements"] &&
           item_tax_rates["elements"].any? { |tr| tr["id"] == tax_rate_id }
          logger.info "Tax rate #{tax_rate_id} already applied to item #{item_id}, skipping"
          return true
        end

        payload = {
          "taxRate" => { "id" => tax_rate_id }
        }
        logger.info "Request payload: #{payload.inspect}"
        make_request(:post, endpoint("items/#{item_id}/tax_rates"), payload)
      end

      def remove_tax_rate_from_item(item_id, tax_rate_id)
        logger.info "=== Removing tax rate #{tax_rate_id} from item #{item_id} ==="
        make_request(:delete, endpoint("items/#{item_id}/tax_rates/#{tax_rate_id}"))
      end

      def get_item_tax_rates(item_id)
        logger.info "=== Fetching tax rates for item #{item_id} ==="
        make_request(:get, endpoint("items/#{item_id}/tax_rates"))
      end

      def apply_tax_rate_to_order(order_id, tax_rate_id)
        logger.info "=== Applying tax rate #{tax_rate_id} to order #{order_id} ==="

        # Check if this tax rate is already applied to the order
        order_tax_rates = get_order_tax_rates(order_id)
        if order_tax_rates && order_tax_rates["elements"] &&
           order_tax_rates["elements"].any? { |tr| tr["id"] == tax_rate_id }
          logger.info "Tax rate #{tax_rate_id} already applied to order #{order_id}, skipping"
          return true
        end

        payload = {
          "taxRate" => { "id" => tax_rate_id }
        }
        logger.info "Request payload: #{payload.inspect}"
        make_request(:post, endpoint("orders/#{order_id}/tax_rates"), payload)
      end

      def remove_tax_rate_from_order(order_id, tax_rate_id)
        logger.info "=== Removing tax rate #{tax_rate_id} from order #{order_id} ==="
        make_request(:delete, endpoint("orders/#{order_id}/tax_rates/#{tax_rate_id}"))
      end

      def get_order_tax_rates(order_id)
        logger.info "=== Fetching tax rates for order #{order_id} ==="
        make_request(:get, endpoint("orders/#{order_id}/tax_rates"))
      end

      def create_standard_tax_rates
        logger.info "=== Creating standard tax rates for a restaurant ==="

        # Check if standard tax rates already exist
        existing_tax_rates = get_tax_rates
        if existing_tax_rates && existing_tax_rates["elements"] && !existing_tax_rates["elements"].empty?
          standard_names = ["Sales Tax", "Alcohol Tax", "Takeout Tax", "No Tax"]

          existing_standard = existing_tax_rates["elements"].select { |tr| standard_names.include?(tr["name"]) }

          if existing_standard.size >= 3
            logger.info "Found #{existing_standard.size} standard tax rates already existing, skipping creation"
            return existing_standard
          end
        end

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
        success_count = 0
        error_count = 0

        logger.info "Creating #{standard_tax_rates.size} standard tax rates"

        standard_tax_rates.each_with_index do |tax_rate_data, index|
          logger.info "Creating tax rate #{index + 1}/#{standard_tax_rates.size}: #{tax_rate_data["name"]}"

          begin
            tax_rate = create_tax_rate(tax_rate_data)
            if tax_rate && tax_rate["id"]
              logger.info "Successfully created tax rate: #{tax_rate["name"]} with ID: #{tax_rate["id"]}"
              created_tax_rates << tax_rate
              success_count += 1
            else
              logger.warn "Created tax rate but received unexpected response: #{tax_rate.inspect}"
              error_count += 1
            end
          rescue StandardError => e
            logger.error "Failed to create tax rate #{tax_rate_data["name"]}: #{e.message}"
            error_count += 1
          end
        end

        logger.info "Created #{success_count} tax rates successfully, #{error_count} failed"

        # Set default tax rate (try but don't fail if it doesn't work)
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

      def assign_category_tax_rates(categories, tax_rates)
        logger.info "=== Assigning appropriate tax rates to categories ==="

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

        assignment_count = 0
        error_count = 0

        # Process each category
        categories.each_with_index do |category, index|
          logger.info "Processing category #{index + 1}/#{categories.size}: #{category["name"]}"
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

          unless items_response && items_response["elements"]
            logger.warn "No items found for category #{category["name"]}"
            next
          end

          logger.info "Found #{items_response["elements"].size} items in category #{category["name"]}"

          # Apply tax rates to each item
          items_response["elements"].each_with_index do |item, item_index|
            logger.info "Processing item #{item_index + 1}/#{items_response["elements"].size}: #{item["name"]}"

            # Check if item already has tax rates assigned
            item_tax_rates = get_item_tax_rates(item["id"])
            if item_tax_rates && item_tax_rates["elements"] && !item_tax_rates["elements"].empty?
              logger.info "Item #{item["name"]} already has tax rates assigned, skipping"
              next
            end

            # Apply applicable tax rates
            applicable_tax_rates.each do |tax_rate|
              logger.info "Applying tax rate #{tax_rate["name"]} to item #{item["name"]}"
              begin
                apply_tax_rate_to_item(item["id"], tax_rate["id"])
                assignment_count += 1
              rescue StandardError => e
                logger.error "Failed to apply tax rate: #{e.message}"
                error_count += 1
              end
            end
          end
        end

        logger.info "=== Finished assigning tax rates: #{assignment_count} assignments, #{error_count} errors ==="
        true
      end

      def calculate_tax(amount, tax_rate)
        logger.info "=== Calculating tax for amount #{amount} with rate #{tax_rate}% ==="

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
