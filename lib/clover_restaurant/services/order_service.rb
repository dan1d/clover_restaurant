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

      def get_order(order_id)
        logger.info "=== Fetching order #{order_id} for merchant #{@config.merchant_id} ==="
        make_request(:get, endpoint("orders/#{order_id}"))
      end

      def create_order(order_data = {})
        logger.info "=== Creating a new order for merchant #{@config.merchant_id} ==="
        logger.info "Order data: #{order_data.inspect}"
        make_request(:post, endpoint("orders"), order_data)
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

        # Check if a similar service charge is already applied to the order
        existing_charges = get_service_charges(order_id)

        if existing_charges && existing_charges["elements"] && service_charge_data["name"] && existing_charges["elements"].any? do |sc|
          sc["name"] == service_charge_data["name"]
        end
          logger.info "Service charge '#{service_charge_data["name"]}' already applied to order #{order_id}, skipping"
          return existing_charges["elements"].find { |sc| sc["name"] == service_charge_data["name"] }
        end

        logger.info "Service charge data: #{service_charge_data.inspect}"
        make_request(:post, endpoint("orders/#{order_id}/service_charges"), service_charge_data)
      end

      def remove_service_charge(order_id, service_charge_id)
        logger.info "=== Removing service charge #{service_charge_id} from order #{order_id} ==="
        make_request(:delete, endpoint("orders/#{order_id}/service_charges/#{service_charge_id}"))
      end

      def calculate_order_total(order_id)
        logger.info "=== Calculating total for order #{order_id} ==="
        order = get_order(order_id)

        return 0 unless order && order["lineItems"] && order["lineItems"]["elements"]

        total = 0

        # Calculate line items total
        order["lineItems"]["elements"].each do |line_item|
          item_total = line_item["price"]

          # Add modifications
          if line_item["modifications"] && line_item["modifications"]["elements"]
            line_item["modifications"]["elements"].each do |mod|
              item_total += mod["price"]
            end
          end

          # Multiply by quantity
          item_total *= line_item["quantity"]

          total += item_total
        end

        # Subtract discounts
        if order["discounts"] && order["discounts"]["elements"]
          order["discounts"]["elements"].each do |discount|
            if discount["percentage"]
              discount_amount = (total * discount["percentage"] / 100.0).round
              total -= discount_amount
            else
              total -= discount["amount"]
            end
          end
        end

        # Add service charges
        if order["serviceCharges"] && order["serviceCharges"]["elements"]
          order["serviceCharges"]["elements"].each do |service_charge|
            if service_charge["percentage"]
              charge_amount = (total * service_charge["percentage"] / 100.0).round
              total += charge_amount
            else
              total += service_charge["amount"]
            end
          end
        end

        # Calculate tax
        if order["taxRates"] && order["taxRates"]["elements"]
          tax_total = 0
          order["taxRates"]["elements"].each do |tax_rate|
            tax_amount = (total * tax_rate["rate"] / 100.0).round
            tax_total += tax_amount
          end
          total += tax_total
        end

        total
      end

      def update_order_total(order_id, total)
        logger.info "=== Updating order #{order_id} total to #{total} ==="
        make_request(:post, endpoint("orders/#{order_id}"), { "total" => total })
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

      def get_service_charges(order_id)
        logger.info "=== Fetching service charges for order #{order_id} ==="
        make_request(:get, endpoint("orders/#{order_id}/service_charges"))
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

      def create_random_order(items, employee_id = nil, customer_id = nil, options = {})
        logger.info "=== Creating random order ==="

        # Create a new order
        order_data = {}
        order_data["employee"] = { "id" => employee_id } if employee_id

        order = create_order(order_data)

        unless order && order["id"]
          logger.error "Failed to create order"
          return nil
        end

        order_id = order["id"]

        # Add customer if provided
        add_customer_to_order(order_id, customer_id) if customer_id

        # Set dining option deterministically instead of randomly
        dining_option = options[:dining_option] || (order_id.hash.abs.even? ? "HERE" : "TO_GO")
        set_dining_option(order_id, dining_option)

        # Add deterministic number of items instead of random
        num_items = options[:num_items] || (order_id.hash.abs % 5) + 1 # 1-5 items

        # Select items deterministically
        item_indices = []
        for i in 0..(num_items - 1)
          item_indices << ((order_id.hash.abs + i) % items.size)
        end

        selected_items = item_indices.map { |idx| items[idx] }

        selected_items.each_with_index do |item, index|
          # Deterministic quantity
          quantity = ((order_id.hash.abs + index) % 3) + 1 # 1-3 quantity

          line_item = add_line_item(order_id, item["id"], quantity)

          # Add note deterministically
          next unless (order_id.hash.abs + index) % 10 < 3 # 30% chance

          notes = ["Extra hot", "No onions", "On the side", "Light sauce", "Well done"]
          note_idx = (order_id.hash.abs + index) % notes.size
          add_note_to_line_item(order_id, line_item["id"], notes[note_idx])

          # TODO: Consider adding modifications with similar deterministic approach
        end

        # Add discount deterministically
        if order_id.hash.abs % 10 < 4 # 40% chance
          discount_service = DiscountService.new(@config)
          discounts = discount_service.get_discounts

          if discounts && discounts["elements"] && !discounts["elements"].empty?
            discount_idx = order_id.hash.abs % discounts["elements"].size
            discount = discounts["elements"][discount_idx]

            discount_data = { "discount" => { "id" => discount["id"] } }
            add_discount(order_id, discount_data)
          end
        end

        # Calculate and update total
        total = calculate_order_total(order_id)
        update_order_total(order_id, total)

        # Add order note deterministically
        if order_id.hash.abs % 10 < 3 # 30% chance
          notes = ["Birthday celebration", "Anniversary", "Please deliver ASAP", "Call on arrival"]
          note_idx = order_id.hash.abs % notes.size
          add_note_to_order(order_id, notes[note_idx])
        end

        # Return the completed order
        get_order(order_id)
      end
    end
  end
end
