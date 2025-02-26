# lib/clover_restaurant/services/order_service.rb
module CloverRestaurant
  module Services
    class OrderService < BaseService
      def get_orders(limit = 50, offset = 0, filter = nil)
        logger.info "Fetching orders for merchant #{@config.merchant_id}"
        query_params = { limit: limit, offset: offset }
        query_params[:filter] = filter if filter

        make_request(:get, endpoint("orders"), nil, query_params)
      end

      def get_order(order_id)
        logger.info "Fetching order #{order_id} for merchant #{@config.merchant_id}"
        make_request(:get, endpoint("orders/#{order_id}"))
      end

      def create_order(order_data = {})
        logger.info "Creating a new order for merchant #{@config.merchant_id}"
        make_request(:post, endpoint("orders"), order_data)
      end

      def update_order(order_id, order_data)
        logger.info "Updating order #{order_id} for merchant #{@config.merchant_id}"
        make_request(:post, endpoint("orders/#{order_id}"), order_data)
      end

      def delete_order(order_id)
        logger.info "Deleting order #{order_id} for merchant #{@config.merchant_id}"
        make_request(:delete, endpoint("orders/#{order_id}"))
      end

      def add_line_item(order_id, item_id, quantity = 1, modifications = [], notes = nil)
        logger.info "Adding item #{item_id} to order #{order_id}"

        line_item_data = {
          "item" => { "id" => item_id },
          "quantity" => quantity
        }

        line_item_data["note"] = notes if notes

        line_item_data["modifications"] = modifications if modifications && !modifications.empty?

        make_request(:post, endpoint("orders/#{order_id}/line_items"), line_item_data)
      end

      def update_line_item(order_id, line_item_id, line_item_data)
        logger.info "Updating line item #{line_item_id} in order #{order_id}"
        make_request(:post, endpoint("orders/#{order_id}/line_items/#{line_item_id}"), line_item_data)
      end

      def delete_line_item(order_id, line_item_id)
        logger.info "Deleting line item #{line_item_id} from order #{order_id}"
        make_request(:delete, endpoint("orders/#{order_id}/line_items/#{line_item_id}"))
      end

      def add_modification(order_id, line_item_id, modifier_id)
        logger.info "Adding modification #{modifier_id} to line item #{line_item_id}"
        make_request(:post, endpoint("orders/#{order_id}/line_items/#{line_item_id}/modifications"), {
                       "modifier" => { "id" => modifier_id }
                     })
      end

      def remove_modification(order_id, line_item_id, modification_id)
        logger.info "Removing modification #{modification_id} from line item #{line_item_id}"
        make_request(:delete,
                     endpoint("orders/#{order_id}/line_items/#{line_item_id}/modifications/#{modification_id}"))
      end

      def add_discount(order_id, discount_data)
        logger.info "Adding discount to order #{order_id}"
        make_request(:post, endpoint("orders/#{order_id}/discounts"), discount_data)
      end

      def remove_discount(order_id, discount_id)
        logger.info "Removing discount #{discount_id} from order #{order_id}"
        make_request(:delete, endpoint("orders/#{order_id}/discounts/#{discount_id}"))
      end

      def add_service_charge(order_id, service_charge_data)
        logger.info "Adding service charge to order #{order_id}"
        make_request(:post, endpoint("orders/#{order_id}/service_charges"), service_charge_data)
      end

      def remove_service_charge(order_id, service_charge_id)
        logger.info "Removing service charge #{service_charge_id} from order #{order_id}"
        make_request(:delete, endpoint("orders/#{order_id}/service_charges/#{service_charge_id}"))
      end

      def calculate_order_total(order_id)
        logger.info "Calculating total for order #{order_id}"
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
        logger.info "Updating order #{order_id} total to #{total}"
        make_request(:post, endpoint("orders/#{order_id}"), { "total" => total })
      end

      def void_order(order_id, reason = "Order voided")
        logger.info "Voiding order #{order_id}"
        make_request(:post, endpoint("orders/#{order_id}"), { "state" => "VOIDED", "voidReason" => reason })
      end

      def add_customer_to_order(order_id, customer_id)
        logger.info "Adding customer #{customer_id} to order #{order_id}"
        make_request(:post, endpoint("orders/#{order_id}"),
                     { "customers" => { "elements" => [{ "id" => customer_id }] } })
      end

      def set_dining_option(order_id, dining_option)
        logger.info "Setting dining option to #{dining_option} for order #{order_id}"
        unless %w[HERE TO_GO DELIVERY].include?(dining_option)
          logger.error "Invalid dining option: #{dining_option}. Must be one of HERE, TO_GO, DELIVERY."
          return false
        end

        make_request(:post, endpoint("orders/#{order_id}"), { "diningOption" => dining_option })
      end

      def get_line_items(order_id)
        logger.info "Fetching line items for order #{order_id}"
        make_request(:get, endpoint("orders/#{order_id}/line_items"))
      end

      def get_payments(order_id)
        logger.info "Fetching payments for order #{order_id}"
        make_request(:get, endpoint("orders/#{order_id}/payments"))
      end

      def get_modifications(order_id, line_item_id)
        logger.info "Fetching modifications for line item #{line_item_id} in order #{order_id}"
        make_request(:get, endpoint("orders/#{order_id}/line_items/#{line_item_id}/modifications"))
      end

      def get_discounts(order_id)
        logger.info "Fetching discounts for order #{order_id}"
        make_request(:get, endpoint("orders/#{order_id}/discounts"))
      end

      def get_service_charges(order_id)
        logger.info "Fetching service charges for order #{order_id}"
        make_request(:get, endpoint("orders/#{order_id}/service_charges"))
      end

      def add_note_to_order(order_id, note)
        logger.info "Adding note to order #{order_id}"
        make_request(:post, endpoint("orders/#{order_id}"), { "note" => note })
      end

      def add_note_to_line_item(order_id, line_item_id, note)
        logger.info "Adding note to line item #{line_item_id} in order #{order_id}"
        make_request(:post, endpoint("orders/#{order_id}/line_items/#{line_item_id}"), { "note" => note })
      end

      def create_random_order(items, employee_id = nil, customer_id = nil, options = {})
        logger.info "Creating random order"

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

        # Set dining option if provided
        dining_option = options[:dining_option] || %w[HERE TO_GO].sample
        set_dining_option(order_id, dining_option)

        # Add random items (between 1 and 5)
        num_items = options[:num_items] || rand(1..5)
        selected_items = items.sample(num_items)

        selected_items.each do |item|
          # Random quantity between 1 and 3
          quantity = rand(1..3)

          line_item = add_line_item(order_id, item["id"], quantity)

          # Add note sometimes
          if rand < 0.3 # 30% chance
            note = ["Extra hot", "No onions", "On the side", "Light sauce", "Well done"].sample
            add_note_to_line_item(order_id, line_item["id"], note)
          end

          # TODO: Add modifications
        end

        # Add discount sometimes
        if rand < 0.4 # 40% chance
          discount_data = if rand < 0.5
                            # Percentage discount
                            { "percentage" => rand(5..20) }
                          else
                            # Fixed amount discount
                            { "amount" => rand(100..500) }
                          end

          discount_data["name"] = ["Happy Hour", "First Time Customer", "Loyalty Discount", "Senior Discount"].sample

          add_discount(order_id, discount_data)
        end

        # Calculate and update total
        total = calculate_order_total(order_id)
        update_order_total(order_id, total)

        # Add order note sometimes
        if rand < 0.3 # 30% chance
          note = ["Birthday celebration", "Anniversary", "Please deliver ASAP", "Call on arrival"].sample
          add_note_to_order(order_id, note)
        end

        # Return the completed order
        get_order(order_id)
      end
    end
  end
end
