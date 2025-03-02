# lib/clover_restaurant/services/discount_service.rb
module CloverRestaurant
  module Services
    class DiscountService < BaseService
      def get_discounts(limit = 100, offset = 0)
        logger.info "=== Fetching discounts for merchant #{@config.merchant_id} ==="
        make_request(:get, endpoint("discounts"), nil, { limit: limit, offset: offset })
      end

      def get_discount(discount_id)
        logger.info "=== Fetching discount #{discount_id} for merchant #{@config.merchant_id} ==="
        make_request(:get, endpoint("discounts/#{discount_id}"))
      end

      def create_discount(discount_data)
        logger.info "=== Creating new discount for merchant #{@config.merchant_id} ==="

        # Make a copy of the data to avoid modifying the original
        data_to_send = discount_data.dup

        # Ensure proper format according to Clover API:
        # - 'amount' should be an integer and negative for discounts
        # - 'percentage' should be an integer, not a boolean
        # - remove any 'percentage' field if it's false or nil

        # Handle amount field (ensure it's negative for discounts)
        if data_to_send.key?("amount") && data_to_send["amount"] > 0
          logger.info "Converting positive amount to negative: #{data_to_send["amount"]} -> #{-data_to_send["amount"].abs}"
          data_to_send["amount"] = -data_to_send["amount"].abs
        end

        # Remove percentage field if it's false/nil, otherwise ensure it's an integer
        if data_to_send.key?("percentage")
          if data_to_send["percentage"] == false || data_to_send["percentage"].nil?
            logger.info "Removing 'percentage' field because it's #{data_to_send["percentage"].inspect}"
            data_to_send.delete("percentage")
          elsif !data_to_send["percentage"].is_a?(Integer)
            logger.info "Converting percentage to integer: #{data_to_send["percentage"]} -> #{data_to_send["percentage"].to_i}"
            data_to_send["percentage"] = data_to_send["percentage"].to_i
          end
        end

        logger.info "Discount Data to send: #{data_to_send.inspect}"
        response = make_request(:post, endpoint("discounts"), data_to_send)

        if response && response["id"]
          logger.info "✅ Successfully created discount '#{response["name"]}' with ID: #{response["id"]}"
        else
          logger.error "❌ ERROR: Discount creation failed. Response: #{response.inspect}"
        end

        response
      end

      def update_discount(discount_id, discount_data)
        logger.info "=== Updating discount #{discount_id} for merchant #{@config.merchant_id} ==="

        # IMPORTANT: Clover API requires discount amounts to be negative
        if discount_data["amount"] && discount_data["amount"] > 0
          logger.info "Converting positive amount to negative: #{discount_data["amount"]} -> #{-discount_data["amount"]}"
          discount_data["amount"] = -discount_data["amount"]
        end

        logger.info "Updated discount data: #{discount_data.inspect}"
        make_request(:post, endpoint("discounts/#{discount_id}"), discount_data)
      end

      def delete_discount(discount_id)
        logger.info "=== Deleting discount #{discount_id} for merchant #{@config.merchant_id} ==="
        make_request(:delete, endpoint("discounts/#{discount_id}"))
      end

      def apply_discount_to_order(order_id, discount_data)
        logger.info "=== Applying discount to order #{order_id} ==="

        # Check if discount is already applied to this order
        existing_discounts = get_order_discounts(order_id)
        if existing_discounts && existing_discounts["elements"] && discount_data["discount"] && discount_data["discount"]["id"]
          discount_id = discount_data["discount"]["id"]
          if existing_discounts["elements"].any? { |d| d["discount"] && d["discount"]["id"] == discount_id }
            logger.info "Discount #{discount_id} already applied to order #{order_id}, skipping"
            return existing_discounts["elements"].find { |d| d["discount"]["id"] == discount_id }
          end
        end

        logger.info "Discount data: #{discount_data.inspect}"
        make_request(:post, endpoint("orders/#{order_id}/discounts"), discount_data)
      end

      def get_order_discounts(order_id)
        logger.info "=== Fetching discounts for order #{order_id} ==="
        make_request(:get, endpoint("orders/#{order_id}/discounts"))
      end

      def remove_discount_from_order(order_id, order_discount_id)
        logger.info "=== Removing discount from order #{order_id} ==="
        make_request(:delete, endpoint("orders/#{order_id}/discounts/#{order_discount_id}"))
      end

      def apply_line_item_discount(order_id, line_item_id, discount_data)
        logger.info "=== Applying discount to line item #{line_item_id} in order #{order_id} ==="

        # Check if discount is already applied to this line item
        existing_discounts = get_line_item_discounts(order_id, line_item_id)
        if existing_discounts && existing_discounts["elements"] && discount_data["discount"] && discount_data["discount"]["id"]
          discount_id = discount_data["discount"]["id"]
          if existing_discounts["elements"].any? { |d| d["discount"] && d["discount"]["id"] == discount_id }
            logger.info "Discount #{discount_id} already applied to line item #{line_item_id}, skipping"
            return existing_discounts["elements"].find { |d| d["discount"]["id"] == discount_id }
          end
        end

        logger.info "Discount data: #{discount_data.inspect}"
        make_request(:post, endpoint("orders/#{order_id}/line_items/#{line_item_id}/discounts"), discount_data)
      end

      def get_line_item_discounts(order_id, line_item_id)
        logger.info "=== Fetching discounts for line item #{line_item_id} in order #{order_id} ==="
        make_request(:get, endpoint("orders/#{order_id}/line_items/#{line_item_id}/discounts"))
      end

      def remove_line_item_discount(order_id, line_item_id, discount_id)
        logger.info "=== Removing discount from line item #{line_item_id} in order #{order_id} ==="
        make_request(:delete, endpoint("orders/#{order_id}/line_items/#{line_item_id}/discounts/#{discount_id}"))
      end

      def create_standard_discounts
        logger.info "=== Creating standard restaurant discounts ==="

        # Check if standard discounts already exist
        existing_discounts = get_discounts
        if existing_discounts && existing_discounts["elements"] && existing_discounts["elements"].size >= 5
          standard_names = ["Happy Hour", "Senior Discount", "Military Discount", "Employee Discount",
                            "First-Time Customer", "Lunch Special", "10% Off", "15% Off", "20% Off"]

          existing_standard = existing_discounts["elements"].select { |d| standard_names.include?(d["name"]) }

          if existing_standard.size >= 5
            logger.info "Found #{existing_standard.size} standard discounts already existing, skipping creation"
            return existing_standard
          end
        end

        standard_discounts = [
          {
            "name" => "Happy Hour",
            "percentage" => 15,
            "enabled" => true
          },
          {
            "name" => "Senior Discount",
            "percentage" => 10,
            "enabled" => true
          },
          {
            "name" => "Military Discount",
            "percentage" => 15,
            "enabled" => true
          },
          {
            "name" => "Employee Discount",
            "percentage" => 25,
            "enabled" => true
          },
          {
            "name" => "First-Time Customer",
            "percentage" => 20,
            "enabled" => true
          },
          {
            "name" => "Lunch Special",
            "amount" => -500, # $5.00 (negative since it's a discount)
            "enabled" => true
          },
          {
            "name" => "10% Off",
            "percentage" => 10,
            "enabled" => true
          },
          {
            "name" => "15% Off",
            "percentage" => 15,
            "enabled" => true
          },
          {
            "name" => "20% Off",
            "percentage" => 20,
            "enabled" => true
          },
          {
            "name" => "Birthday Discount",
            "percentage" => 25,
            "enabled" => true
          },
          {
            "name" => "$5 Off",
            "amount" => -500, # $5.00 (negative since it's a discount)
            "enabled" => true
          },
          {
            "name" => "$10 Off",
            "amount" => -1000, # $10.00 (negative since it's a discount)
            "enabled" => true
          }
        ]

        created_discounts = []
        success_count = 0
        error_count = 0

        standard_discounts.each_with_index do |discount_data, index|
          logger.info "Creating discount #{index + 1}/#{standard_discounts.size}: #{discount_data["name"]}"

          begin
            discount = create_discount(discount_data)
            if discount && discount["id"]
              logger.info "Successfully created discount: #{discount["name"]} with ID: #{discount["id"]}"
              created_discounts << discount
              success_count += 1
            else
              logger.warn "Created discount but received unexpected response: #{discount.inspect}"
              error_count += 1
            end
          rescue StandardError => e
            logger.error "Failed to create discount #{discount_data["name"]}: #{e.message}"
            error_count += 1
          end
        end

        logger.info "=== Finished creating discounts: #{success_count} successful, #{error_count} failed ==="
        created_discounts
      end

      def apply_random_discount_to_order(order_id, available_discounts = nil)
        logger.info "=== Applying random discount to order #{order_id} ==="

        # Get available discounts if not provided
        if available_discounts.nil? || available_discounts.empty?
          logger.info "No discounts provided, fetching available discounts"
          discounts_response = get_discounts

          available_discounts = if discounts_response && discounts_response["elements"] && !discounts_response["elements"].empty?
                                  discounts_response["elements"]
                                else
                                  # Create standard discounts
                                  logger.info "No existing discounts found, creating standard discounts"
                                  create_standard_discounts
                                end
        end

        if available_discounts.nil? || available_discounts.empty?
          logger.error "No discounts available to apply"
          return false
        end

        logger.info "Found #{available_discounts.size} available discounts"

        # Use a deterministic selection based on order ID to ensure consistency for VCR
        seed = order_id.to_s.chars.map(&:ord).sum % available_discounts.size
        discount = available_discounts[seed]
        logger.info "Selected discount: #{discount["name"]} (ID: #{discount["id"]})"

        # Apply it to the order
        discount_data = {
          "discount" => { "id" => discount["id"] }
        }

        logger.info "Applying discount to order"
        apply_discount_to_order(order_id, discount_data)
      end

      def apply_random_line_item_discount(order_id, line_item_id, available_discounts = nil)
        logger.info "=== Applying random discount to line item #{line_item_id} in order #{order_id} ==="

        # Get available discounts if not provided
        if available_discounts.nil? || available_discounts.empty?
          logger.info "No discounts provided, fetching available discounts"
          discounts_response = get_discounts

          available_discounts = if discounts_response && discounts_response["elements"] && !discounts_response["elements"].empty?
                                  discounts_response["elements"]
                                else
                                  # Create standard discounts
                                  logger.info "No existing discounts found, creating standard discounts"
                                  create_standard_discounts
                                end
        end

        if available_discounts.nil? || available_discounts.empty?
          logger.error "No discounts available to apply"
          return false
        end

        logger.info "Found #{available_discounts.size} available discounts"

        # Use a deterministic selection based on line item ID to ensure consistency for VCR
        seed = line_item_id.to_s.chars.map(&:ord).sum % available_discounts.size
        discount = available_discounts[seed]
        logger.info "Selected discount: #{discount["name"]} (ID: #{discount["id"]})"

        # Apply it to the line item
        discount_data = {
          "discount" => { "id" => discount["id"] }
        }

        logger.info "Applying discount to line item"
        apply_line_item_discount(order_id, line_item_id, discount_data)
      end

      def create_limited_time_offer(name, discount_amount, is_percentage = true, start_date = nil, end_date = nil)
        logger.info "=== Creating limited time offer: #{name} ==="

        # Check if this limited time offer already exists
        existing_discounts = get_discounts
        if existing_discounts && existing_discounts["elements"]
          existing_offer = existing_discounts["elements"].find { |d| d["name"] == "LIMITED TIME: #{name}" }
          if existing_offer
            logger.info "Limited time offer '#{name}' already exists with ID: #{existing_offer["id"]}, skipping creation"
            return existing_offer
          end
        end

        # Set default dates if not provided
        start_date ||= Date.today
        end_date ||= Date.today + 30 # 30 days from today

        discount_data = {
          "name" => "LIMITED TIME: #{name}",
          "enabled" => true,
          "startDate" => start_date.strftime("%Y-%m-%d"),
          "endDate" => end_date.strftime("%Y-%m-%d")
        }

        # Set either percentage or fixed amount
        if is_percentage
          discount_data["percentage"] = discount_amount.to_i
        else
          # IMPORTANT: Make sure amount is negative for a discount
          discount_amount = -discount_amount.to_i.abs
          discount_data["amount"] = discount_amount
        end

        logger.info "Limited time offer data: #{discount_data.inspect}"
        create_discount(discount_data)
      end

      def create_combo_deal(name, amount)
        logger.info "=== Creating combo deal: #{name} ==="

        # Check if this combo deal already exists
        existing_discounts = get_discounts
        if existing_discounts && existing_discounts["elements"]
          existing_combo = existing_discounts["elements"].find { |d| d["name"] == "COMBO: #{name}" }
          if existing_combo
            logger.info "Combo deal '#{name}' already exists with ID: #{existing_combo["id"]}, skipping creation"
            return existing_combo
          end
        end

        # IMPORTANT: Make sure amount is negative for a discount
        amount = -amount.to_i.abs

        discount_data = {
          "name" => "COMBO: #{name}",
          "amount" => amount,
          "enabled" => true
        }

        logger.info "Combo deal data: #{discount_data.inspect}"
        create_discount(discount_data)
      end
    end
  end
end
