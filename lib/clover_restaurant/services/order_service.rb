# lib/clover_restaurant/services/order_service.rb
module CloverRestaurant
  module Services
    class OrderService < BaseService
      def get_orders(limit = 50, offset = 0, filter = nil)
        logger.info "=== Fetching orders for merchant #{@config.merchant_id} ==="
        query_params = { limit: limit, offset: offset }
        query_params[:filter] = filter if filter

        make_request(:get, endpoint("orders"), nil, query_params)
      end

      def update_order_state(order_id, state)
        logger.info "🔄 Updating order #{order_id} state to #{state}..."
        payload = { "state" => state }
        response = make_request(:post, endpoint("orders/#{order_id}"), payload)

        if response
          logger.info "✅ Order #{order_id} updated to state: #{state}"
        else
          logger.error "❌ Failed to update order #{order_id} state."
        end
      end

      def get_order(order_id)
        logger.info "=== Fetching order #{order_id} for merchant #{@config.merchant_id} ==="
        make_request(:get, endpoint("orders/#{order_id}"))
      end

      def create_order(order_data = {})
        logger.info "=== Creating a new order for merchant #{@config.merchant_id} ==="

        # # Ensure unique order creation
        # existing_orders = get_orders(100, 0)
        # similar_order = existing_orders["elements"]&.find do |order|
        #   order["employee"]["id"] == order_data["employee"]["id"] &&
        #     order["customers"]&.any? { |c| c["id"] == order_data["customers"].first["id"] }
        # end

        # if similar_order
        #   logger.info "✅ Found existing order (#{similar_order["id"]}). Skipping creation."
        #   return similar_order
        # end

        order = make_request(:post, endpoint("orders"), order_data)
        return nil unless order && order["id"]

        order_id = order["id"]
        total_price = 0

        # Select random items
        items = begin
          @services_manager.inventory.get_items["elements"]
        rescue StandardError
          []
        end

        num_items = rand(1..4)
        selected_items = items.sample(num_items)

        selected_items.each do |item|
          quantity = rand(1..2)
          total_price += (item["price"] || 0) * quantity
          add_line_item(order_id, item["id"], quantity)
        end

        # Apply discount randomly
        discounts = begin
          @services_manager.discount.get_discounts["elements"]
        rescue StandardError
          []
        end
        if rand < 0.4 && !discounts.empty?
          discount = discounts.sample
          apply_discount(order_id, discount["id"])
        end

        # Finalize order total
        total = calculate_order_total(order_id)
        update_order_total(order_id, total)

        # Process payment after order creation
        payment_service = @services_manager.payment
        payment_service.process_payment(order_id, total, order_data["employee"]["id"], order_data["clientCreatedTime"])

        logger.info "✅ Order #{order_id} created with total: #{total / 100.0} USD from 1 month ago"
        order
      end

      def update_order(order_id, order_data)
        logger.info "=== Updating order #{order_id} for merchant #{@config.merchant_id} ==="
        logger.info "Update data: #{order_data.inspect}"
        make_request(:post, endpoint("orders/#{order_id}"), order_data)
      end

      def delete_order(order_id)
        logger.info "=== Deleting order #{order_id} for merchant #{@config.merchant_id} ==="
        make_request(:delete, endpoint("orders/#{order_id}"))
      end

      def add_line_item(order_id, item_id, quantity = 1, modifications = [], notes = nil)
        logger.info "=== Adding item #{item_id} to order #{order_id} ==="

        # Check if this item is already in the order with same quantity and modifications
        line_items = get_line_items(order_id)
        if line_items && line_items["elements"]
          existing_item = line_items["elements"].find do |li|
            matches = li["item"] && li["item"]["id"] == item_id && li["quantity"] == quantity

            # Check modifications if provided
            if matches && !modifications.empty? && li["modifications"] && li["modifications"]["elements"]
              mod_count = modifications.size
              existing_mod_count = li["modifications"]["elements"].size

              # If counts don't match, it's not the same
              matches = false if mod_count != existing_mod_count

              # If counts match, check each modification
              if matches && mod_count > 0
                modifications.each do |mod|
                  mod_match = li["modifications"]["elements"].any? do |m|
                    m["modifier"] && m["modifier"]["id"] == mod["modifier"]["id"]
                  end

                  matches = false unless mod_match
                end
              end
            end

            # Check notes if provided
            matches = (li["note"] == notes) if matches && notes && li["note"]

            matches
          end

          if existing_item
            logger.info "Item #{item_id} already exists in order #{order_id} with same attributes, skipping"
            return existing_item
          end
        end

        line_item_data = {
          "item" => { "id" => item_id },
          "quantity" => quantity
        }

        line_item_data["note"] = notes if notes

        line_item_data["modifications"] = modifications if modifications && !modifications.empty?

        logger.info "Line item data: #{line_item_data.inspect}"
        make_request(:post, endpoint("orders/#{order_id}/line_items"), line_item_data)
      end

      def update_line_item(order_id, line_item_id, line_item_data)
        logger.info "=== Updating line item #{line_item_id} in order #{order_id} ==="
        logger.info "Update data: #{line_item_data.inspect}"
        make_request(:post, endpoint("orders/#{order_id}/line_items/#{line_item_id}"), line_item_data)
      end

      def delete_line_item(order_id, line_item_id)
        logger.info "=== Deleting line item #{line_item_id} from order #{order_id} ==="
        make_request(:delete, endpoint("orders/#{order_id}/line_items/#{line_item_id}"))
      end

      def apply_discount(order_id, discount_id)
        return
        logger.info "=== Applying discount #{discount_id} to order #{order_id} ==="

        # Fetch discount details to ensure we include the required fields
        discounts = @services_manager.discount.get_discounts["elements"]
        discount = discounts.find { |d| d["id"] == discount_id }

        unless discount
          logger.error "❌ ERROR: Discount ID #{discount_id} not found in available discounts."
          return nil
        end

        # Ensure payload includes either 'amount' or 'percentage'
        payload = {
          "discount" => {
            "id" => discount["id"],
            "name" => discount["name"]
          }
        }

        # payload["discount"]["amount"] = rand(1..10) * 100
        payload["discount"]["percentage"] = "%#{discount["percentage"]}" if discount["percentage"]

        # API requires either amount or percentage
        if payload["discount"]["amount"].nil? && payload["discount"]["percentage"].nil?
          logger.error "❌ ERROR: Discount ID #{discount_id} is missing both amount and percentage."
          payload["discount"]["amount"] = rand(1..10) * 100
          logger.warn "⚠️ Using random amount: #{payload["discount"]["amount"]}"
        end

        response = make_request(:post, endpoint("orders/#{order_id}/discounts"), payload)

        if response && response["id"]
          logger.info "✅ Successfully applied discount ID #{discount_id} to order #{order_id}"
        else
          logger.error "❌ ERROR: Failed to apply discount #{discount_id} to order #{order_id}. Response: #{response.inspect}"
        end

        response
      end

      def add_modification(order_id, line_item_id, modifier_id)
        logger.info "=== Adding modification #{modifier_id} to line item #{line_item_id} ==="

        # Check if this modification is already applied to the line item
        modifications = get_modifications(order_id, line_item_id)
        if modifications && modifications["elements"] && modifications["elements"].any? do |m|
          m["modifier"] && m["modifier"]["id"] == modifier_id
        end
          logger.info "Modification #{modifier_id} already applied to line item #{line_item_id}, skipping"
          return modifications["elements"].find { |m| m["modifier"]["id"] == modifier_id }
        end

        payload = {
          "modifier" => { "id" => modifier_id }
        }

        logger.info "Request payload: #{payload.inspect}"
        make_request(:post, endpoint("orders/#{order_id}/line_items/#{line_item_id}/modifications"), payload)
      end

      def remove_modification(order_id, line_item_id, modification_id)
        logger.info "=== Removing modification #{modification_id} from line item #{line_item_id} ==="
        make_request(:delete,
                     endpoint("orders/#{order_id}/line_items/#{line_item_id}/modifications/#{modification_id}"))
      end

      def add_discount(order_id, discount_data)
        logger.info "=== Adding discount to order #{order_id} ==="

        # Check if a similar discount is already applied to the order
        if discount_data["discount"] && discount_data["discount"]["id"]
          discount_id = discount_data["discount"]["id"]
          existing_discounts = get_discounts(order_id)

          if existing_discounts && existing_discounts["elements"] && existing_discounts["elements"].any? do |d|
            d["discount"] && d["discount"]["id"] == discount_id
          end
            logger.info "Discount #{discount_id} already applied to order #{order_id}, skipping"
            return existing_discounts["elements"].find { |d| d["discount"]["id"] == discount_id }
          end
        end

        logger.info "Discount data: #{discount_data.inspect}"
        make_request(:post, endpoint("orders/#{order_id}/discounts"), discount_data)
      end

      def remove_discount(order_id, discount_id)
        logger.info "=== Removing discount #{discount_id} from order #{order_id} ==="
        make_request(:delete, endpoint("orders/#{order_id}/discounts/#{discount_id}"))
      end

      def add_service_charge(order_id, service_charge_data)
        logger.info "=== Adding service charge to order #{order_id} ==="

        begin
          # Ensure service charges are supported
          service_charge_response = make_request(:get, endpoint("orders/#{order_id}/service_charges"))

          if service_charge_response["status"] == 405
            logger.warn "⚠️ Service charges not supported on this account. Skipping."
            return
          end

          response = make_request(:post, endpoint("orders/#{order_id}/service_charges"), service_charge_data)

          if response && response["id"]
            logger.info "✅ Successfully added service charge: #{service_charge_data["name"]} to order #{order_id}"
          else
            logger.error "❌ Failed to add service charge: #{service_charge_data["name"]} to order #{order_id}"
          end
        rescue StandardError => e
          logger.error "❌ Error adding service charge to order #{order_id}: #{e.message}"
        end
      end

      def remove_service_charge(order_id, service_charge_id)
        logger.info "=== Removing service charge #{service_charge_id} from order #{order_id} ==="
        make_request(:delete, endpoint("orders/#{order_id}/service_charges/#{service_charge_id}"))
      end

      def calculate_order_total(order_id)
        logger.info "=== Calculating total for order #{order_id} ==="
        order = get_order(order_id)

        unless order && order["lineItems"] && order["lineItems"]["elements"]
          logger.error "❌ No line items found for order #{order_id}."
          return 0
        end

        total = 0

        # Calculate line items total
        order["lineItems"]["elements"].each do |line_item|
          item_price = line_item["price"] || 0
          quantity = line_item["quantity"] || 1
          item_total = item_price * quantity

          logger.info "Line item: #{line_item["name"]} (ID: #{line_item["id"]}), Price: #{item_price}, Quantity: #{quantity}, Subtotal: #{item_total}"

          # Add modifications (if any)
          if line_item["modifications"] && line_item["modifications"]["elements"]
            line_item["modifications"]["elements"].each do |mod|
              mod_price = mod["price"] || 0
              item_total += mod_price
              logger.info "Modification: #{mod["name"]} (ID: #{mod["id"]}), Price: #{mod_price}"
            end
          end

          total += item_total
        end

        logger.info "Subtotal before discounts/taxes: #{total}"

        # Subtract discounts (if any)
        if order["discounts"] && order["discounts"]["elements"]
          order["discounts"]["elements"].each do |discount|
            if discount["percentage"]
              discount_amount = (total * discount["percentage"] / 100.0).round
              total -= discount_amount
              logger.info "Applied percentage discount: #{discount["percentage"]}%, Amount: #{discount_amount}"
            else
              total -= discount["amount"] || 0
              logger.info "Applied fixed discount: #{discount["amount"]}"
            end
          end
        end

        logger.info "Total after discounts: #{total}"

        # Add taxes (if any)
        if order["taxRates"] && order["taxRates"]["elements"]
          tax_total = 0
          order["taxRates"]["elements"].each do |tax_rate|
            tax_amount = (total * tax_rate["rate"] / 100.0).round
            tax_total += tax_amount
            logger.info "Applied tax: #{tax_rate["rate"]}%, Amount: #{tax_amount}"
          end
          total += tax_total
        end

        logger.info "Final total: #{total}"
        total
      end

      def update_order_total(order_id, total)
        logger.info "🔄 Updating order #{order_id} total to #{total}..."

        payload = { "total" => total }
        response = make_request(:post, endpoint("orders/#{order_id}"), payload)

        if response
          logger.info "✅ Order #{order_id} updated successfully."
        else
          logger.error "❌ Failed to update order #{order_id}."
        end
      end

      def void_order(order_id, reason = "Order voided")
        logger.info "=== Voiding order #{order_id} ==="

        # Check if order is already voided
        order = get_order(order_id)
        if order && order["state"] == "VOIDED"
          logger.info "Order #{order_id} is already voided, skipping"
          return order
        end

        make_request(:post, endpoint("orders/#{order_id}"), { "state" => "VOIDED", "voidReason" => reason })
      end

      def add_customer_to_order(order_id, customer_id)
        logger.info "=== Adding customer #{customer_id} to order #{order_id} ==="

        # Check if customer is already assigned to this order
        order = get_order(order_id)
        if order && order["customers"] && order["customers"]["elements"] && order["customers"]["elements"].any? do |c|
          c["id"] == customer_id
        end
          logger.info "Customer #{customer_id} already assigned to order #{order_id}, skipping"
          return order
        end

        make_request(:post, endpoint("orders/#{order_id}"),
                     { "customers" => { "elements" => [{ "id" => customer_id }] } })
      end

      def set_dining_option(order_id, dining_option)
        logger.info "=== Setting dining option to #{dining_option} for order #{order_id} ==="

        # Validate dining option
        unless %w[HERE TO_GO DELIVERY].include?(dining_option)
          logger.error "Invalid dining option: #{dining_option}. Must be one of HERE, TO_GO, DELIVERY."
          return false
        end

        # Check if dining option is already set
        order = get_order(order_id)
        if order && order["diningOption"] == dining_option
          logger.info "Dining option for order #{order_id} is already set to #{dining_option}, skipping"
          return order
        end

        make_request(:post, endpoint("orders/#{order_id}"), { "diningOption" => dining_option })
      end

      def get_line_items(order_id)
        logger.info "=== Fetching line items for order #{order_id} ==="
        make_request(:get, endpoint("orders/#{order_id}/line_items"))
      end

      def get_payments(order_id)
        logger.info "=== Fetching payments for order #{order_id} ==="
        make_request(:get, endpoint("orders/#{order_id}/payments"))
      end

      def get_modifications(order_id, line_item_id)
        logger.info "=== Fetching modifications for line item #{line_item_id} in order #{order_id} ==="
        make_request(:get, endpoint("orders/#{order_id}/line_items/#{line_item_id}/modifications"))
      end

      def get_discounts(order_id)
        logger.info "=== Fetching discounts for order #{order_id} ==="
        make_request(:get, endpoint("orders/#{order_id}/discounts"))
      end

      def add_note_to_order(order_id, note)
        logger.info "=== Adding note to order #{order_id} ==="

        # Check if order already has this note
        order = get_order(order_id)
        if order && order["note"] == note
          logger.info "Order #{order_id} already has note '#{note}', skipping"
          return order
        end

        make_request(:post, endpoint("orders/#{order_id}"), { "note" => note })
      end

      def add_note_to_line_item(order_id, line_item_id, note)
        logger.info "=== Adding note to line item #{line_item_id} in order #{order_id} ==="

        # Check if line item already has this note
        line_items = get_line_items(order_id)
        if line_items && line_items["elements"]
          line_item = line_items["elements"].find { |li| li["id"] == line_item_id }
          if line_item && line_item["note"] == note
            logger.info "Line item #{line_item_id} already has note '#{note}', skipping"
            return line_item
          end
        end

        make_request(:post, endpoint("orders/#{order_id}/line_items/#{line_item_id}"), { "note" => note })
      end

      def create_random_order(items, discounts = [], modifiers = [], employees = [], customers = [], options = {})
        logger.info "=== Creating random order efficiently ==="

        order_data = {}
        employee = employees.sample
        order_data["employee"] = { "id" => employee["id"] } if employee

        order = create_order(order_data)
        return nil unless order && order["id"]

        order_id = order["id"]
        customer = customers.sample
        add_customer_to_order(order_id, customer["id"]) if customer

        # Deterministic dining option
        dining_option = options[:dining_option] || (order_id.hash.even? ? "HERE" : "TO_GO")
        set_dining_option(order_id, dining_option)

        # Select deterministic number of items (1-5)
        num_items = options[:num_items] || (order_id.hash % 5) + 1
        selected_items = items.sample(num_items)

        # Batch-create line items
        line_items_data = selected_items.map.with_index do |item, index|
          quantity = ((order_id.hash + index) % 3) + 1
          {
            "item" => { "id" => item["id"] },
            "quantity" => quantity
          }
        end
        batch_add_line_items(order_id, line_items_data)

        # Apply discounts (40% chance)
        if order_id.hash % 10 < 4 && !discounts.empty?
          # discount = discounts.sample
          # apply_discount(order_id, discount["id"])
        end

        # Calculate and update total
        total = calculate_order_total(order_id)
        update_order_total(order_id, total)

        # Order note (30% chance)
        notes = ["Birthday celebration", "Anniversary", "Please deliver ASAP", "Call on arrival"]
        add_note_to_order(order_id, notes.sample) if order_id.hash % 10 < 3

        # Return completed order
        get_order(order_id)
      end

      # 🚀 Optimized: Batch add line items
      def batch_add_line_items(order_id, line_items_data)
        logger.info "=== Batch adding #{line_items_data.size} items to order #{order_id} ==="
        make_request(:post, endpoint("orders/#{order_id}/line_items"), { "elements" => line_items_data })
      end
    end
  end
end
