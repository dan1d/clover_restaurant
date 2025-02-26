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

        # IMPORTANT: Clover API requires discount amounts to be negative
        if discount_data["amount"] && discount_data["amount"] > 0
          logger.info "Converting positive amount to negative: #{discount_data["amount"]} -> #{-discount_data["amount"]}"
          discount_data["amount"] = -discount_data["amount"]
        end

        logger.info "Discount data: #{discount_data.inspect}"
        make_request(:post, endpoint("discounts"), discount_data)
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
        logger.info "Discount data: #{discount_data.inspect}"
        make_request(:post, endpoint("orders/#{order_id}/discounts"), discount_data)
      end

      def remove_discount_from_order(order_id, order_discount_id)
        logger.info "=== Removing discount from order #{order_id} ==="
        make_request(:delete, endpoint("orders/#{order_id}/discounts/#{order_discount_id}"))
      end

      def apply_line_item_discount(order_id, line_item_id, discount_data)
        logger.info "=== Applying discount to line item #{line_item_id} in order #{order_id} ==="
        logger.info "Discount data: #{discount_data.inspect}"
        make_request(:post, endpoint("orders/#{order_id}/line_items/#{line_item_id}/discounts"), discount_data)
      end

      def remove_line_item_discount(order_id, line_item_id, discount_id)
        logger.info "=== Removing discount from line item #{line_item_id} in order #{order_id} ==="
        make_request(:delete, endpoint("orders/#{order_id}/line_items/#{line_item_id}/discounts/#{discount_id}"))
      end

      def create_standard_discounts
        logger.info "=== Creating standard restaurant discounts ==="

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

        # Select a random discount
        discount = available_discounts.sample
        logger.info "Selected random discount: #{discount["name"]} (ID: #{discount["id"]})"

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

        # Select a random discount
        discount = available_discounts.sample
        logger.info "Selected random discount: #{discount["name"]} (ID: #{discount["id"]})"

        # Apply it to the line item
        discount_data = {
          "discount" => { "id" => discount["id"] }
        }

        logger.info "Applying discount to line item"
        apply_line_item_discount(order_id, line_item_id, discount_data)
      end

      def create_limited_time_offer(name, discount_amount, is_percentage = true, start_date = nil, end_date = nil)
        logger.info "=== Creating limited time offer: #{name} ==="

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
