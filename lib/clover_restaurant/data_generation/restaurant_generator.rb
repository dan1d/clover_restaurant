# lib/clover_restaurant/data_generation/restaurant_generator.rb
require "date"
require "active_support/time"

module CloverRestaurant
  module DataGeneration
    class RestaurantGenerator
      attr_reader :data, :services

      def initialize(custom_config = nil)
        @services = CloverRestaurant.services(custom_config)
        @data = {
          inventory: {},
          modifier_groups: [],
          tax_rates: [],
          discounts: [],
          employees: [],
          roles: [],
          tables: [],
          customers: [],
          days: []
        }
        @day_cache = {}
      end

      def setup_restaurant(name = "Claude's Bistro")
        # Cache the restaurant name to avoid unnecessary API calls
        update_merchant_name(name)

        # Create inventory using EntityGenerator
        entities = @services.create_entities

        # Track all created entities
        if entities
          @data[:inventory][:categories] = @services.with_cache(:categories) { @services.inventory.get_categories }
          if @data[:inventory][:categories].is_a?(Hash) && @data[:inventory][:categories]["elements"]
            @data[:inventory][:categories] =
              @data[:inventory][:categories]["elements"]
          end

          @data[:inventory][:items] = @services.with_cache(:items) { @services.inventory.get_items }
          if @data[:inventory][:items].is_a?(Hash) && @data[:inventory][:items]["elements"]
            @data[:inventory][:items] =
              @data[:inventory][:items]["elements"]
          end

          @data[:modifier_groups] = @services.with_cache(:modifier_groups) { @services.modifier.get_modifier_groups }
          if @data[:modifier_groups].is_a?(Hash) && @data[:modifier_groups]["elements"]
            @data[:modifier_groups] =
              @data[:modifier_groups]["elements"]
          end

          @data[:tax_rates] = @services.with_cache(:tax_rates) { @services.tax_rate.get_tax_rates }
          if @data[:tax_rates].is_a?(Hash) && @data[:tax_rates]["elements"]
            @data[:tax_rates] =
              @data[:tax_rates]["elements"]
          end

          @data[:discounts] = @services.with_cache(:discounts) { @services.discount.get_discounts }
          if @data[:discounts].is_a?(Hash) && @data[:discounts]["elements"]
            @data[:discounts] =
              @data[:discounts]["elements"]
          end

          employees_and_roles = @services.with_cache(:employees_and_roles) { @services.employee.get_employees }
          @data[:employees] = employees_and_roles
          if @data[:employees].is_a?(Hash) && @data[:employees]["elements"]
            @data[:employees] =
              @data[:employees]["elements"]
          end

          @data[:roles] = @services.with_cache(:roles) { @services.employee.get_roles }
          @data[:roles] = @data[:roles]["elements"] if @data[:roles].is_a?(Hash) && @data[:roles]["elements"]

          # Get table information
          tables_data = @services.with_cache(:tables) { @services.table.get_tables }
          @data[:tables] = tables_data
          @data[:tables] = @data[:tables]["elements"] if @data[:tables].is_a?(Hash) && @data[:tables]["elements"]

          # Get customer information
          customers_data = @services.with_cache(:customers) { @services.customer.get_customers }
          @data[:customers] = customers_data
          if @data[:customers].is_a?(Hash) && @data[:customers]["elements"]
            @data[:customers] =
              @data[:customers]["elements"]
          end
        end

        # Return the restaurant data
        @data
      end

      def simulate_business_day(date)
        # Check if this day has already been simulated
        return @day_cache[date] if @day_cache[date]

        # Get day of week (0-6, where 0 is Sunday)
        day_of_week = date.wday

        # Establish expected number of orders based on day of week
        # Busier on weekends (Friday, Saturday, Sunday)
        base_order_count = case day_of_week
                           when 0 # Sunday
                             80
                           when 5, 6 # Friday, Saturday
                             100
                           else # Weekdays
                             60
                           end

        # Add some variability but make it deterministic based on date
        date_seed = date.to_s.chars.map(&:ord).sum
        order_count = base_order_count + (date_seed % 20)

        # Keep track of day's data
        day_data = {
          date: date,
          orders: [],
          order_count: order_count,
          total_revenue: 0,
          refunds: [],
          total_refunds: 0,
          dining_options: { "HERE" => 0, "TO_GO" => 0, "DELIVERY" => 0 },
          employee_orders: {},
          items_sold: Hash.new(0),
          customers_served: []
        }

        # Simulate orders for the day
        order_count.times do |i|
          # Create deterministic but varied order time
          hour = 8 + ((date_seed + i) % 14) # 8 AM to 10 PM
          minute = (date_seed + i) % 60
          order_time = Time.new(date.year, date.month, date.day, hour, minute)

          # Select employee deterministically
          employee_index = (date_seed + i) % @data[:employees].size
          employee = @data[:employees][employee_index]

          # Select customer deterministically
          customer_index = (date_seed + i * 3) % @data[:customers].size
          customer = @data[:customers][customer_index]

          # Create order
          order_result = create_order(date, order_time, employee, customer)

          next unless order_result[:order]

          day_data[:orders] << order_result[:order]
          day_data[:total_revenue] += order_result[:total]

          # Track dining options
          dining_option = order_result[:order]["diningOption"] || "HERE"
          day_data[:dining_options][dining_option] += 1

          # Track employee orders
          employee_name = employee["name"]
          day_data[:employee_orders][employee_name] ||= 0
          day_data[:employee_orders][employee_name] += 1

          # Track items sold
          if order_result[:items_sold]
            order_result[:items_sold].each do |item_name, quantity|
              day_data[:items_sold][item_name] += quantity
            end
          end

          # Track customer
          customer_id = customer["id"]
          day_data[:customers_served] << customer_id unless day_data[:customers_served].include?(customer_id)

          # 10% chance of refund - but make it deterministic
          next unless (date_seed + i) % 10 == 0

          refund_result = process_refund(order_result[:order], employee)

          if refund_result[:refund]
            day_data[:refunds] << refund_result[:refund]
            day_data[:total_refunds] += refund_result[:amount]
          end
        end

        # Cache and store the day's data
        @day_cache[date] = day_data
        @data[:days] << day_data

        day_data
      end

      private

      def update_merchant_name(name)
        @services.merchant.update_merchant_property("name", name)
      rescue StandardError
        nil
      end

      def create_order(date, time, employee, customer)
        # Get all items
        items = @data[:inventory][:items]
        return { error: "No items available" } if items.empty?

        # Get order seed for deterministic randomness
        order_seed = "#{date}-#{time}-#{employee["id"]}-#{customer["id"]}".hash.abs

        # Define dining option based on seed
        dining_option = case order_seed % 10
                        when 0, 1, 2 # 30% chance of takeout
                          "TO_GO"
                        when 3 # 10% chance of delivery
                          "DELIVERY"
                        else # 60% chance of dining in
                          "HERE"
                        end

        # Number of items in order (1-5)
        num_items = 1 + (order_seed % 5)

        # Select items deterministically
        selected_items = []
        items_sold = {}

        num_items.times do |i|
          item_index = (order_seed + i * 7) % items.size
          item = items[item_index]

          # Quantity 1-3
          quantity = 1 + ((order_seed + i) % 3)

          selected_items << { item: item, quantity: quantity }

          # Track items sold
          items_sold[item["name"]] = quantity
        end

        # Create order
        order_data = {
          "employee" => { "id" => employee["id"] },
          "diningOption" => dining_option
        }

        begin
          # Create the order
          order = @services.order.create_order(order_data)

          if order && order["id"]
            # Add customer
            @services.order.add_customer_to_order(order["id"], customer["id"])

            # Add line items
            total = 0

            selected_items.each do |item_data|
              item = item_data[:item]
              quantity = item_data[:quantity]

              line_item = @services.order.add_line_item(order["id"], item["id"], quantity)

              # Add the item cost to the total
              total += (item["price"] * quantity) if line_item
            end

            # Add discount (30% chance, based on seed)
            if order_seed % 10 < 3
              discount_data = { "discount" => { "id" => @data[:discounts].sample["id"] } }
              @services.order.add_discount(order["id"], discount_data)

              # Recalculate total
              total = @services.order.calculate_order_total(order["id"])
            end

            # Process payment
            payment_type = order_seed % 10 < 7 ? :cash : :card

            payment = if payment_type == :cash
                        @services.payment.simulate_cash_payment(order["id"], total, { employee_id: employee["id"] })
                      else
                        @services.payment.simulate_card_payment(order["id"], total)
                      end

            # Return data
            return {
              order: order,
              total: total,
              payment: payment,
              items_sold: items_sold
            }
          end
        rescue StandardError => e
          # Log error but don't stop simulation
          puts "Error creating order: #{e.message}" if @config&.log_level == Logger::DEBUG
        end

        # Return failure
        { error: "Failed to create order" }
      end

      def process_refund(order, employee)
        return { error: "Invalid order" } unless order && order["id"]

        begin
          # Get payments for this order
          payments_response = @services.payment.get_payments_for_order(order["id"])

          if payments_response && payments_response["elements"] && !payments_response["elements"].empty?
            payment = payments_response["elements"].first

            # Refund an amount based on order hash (make it deterministic)
            refund_seed = "#{order["id"]}-#{employee["id"]}".hash.abs

            # 20% chance for full refund, 80% chance for partial
            is_full = (refund_seed % 5 == 0)

            if is_full
              # Full refund
              refund = @services.refund.full_refund(payment["id"], "Customer dissatisfied")

              if refund && refund["amount"]
                return {
                  refund: refund,
                  amount: refund["amount"]
                }
              end
            else
              # Partial refund - refund one line item
              line_items_response = @services.order.get_line_items(order["id"])

              if line_items_response && line_items_response["elements"] && !line_items_response["elements"].empty?
                # Select a line item deterministically
                line_item_index = refund_seed % line_items_response["elements"].size
                line_item = line_items_response["elements"][line_item_index]

                # Refund that line item
                refund = @services.refund.refund_line_item(payment["id"], line_item["id"])

                if refund && refund["amount"]
                  return {
                    refund: refund,
                    amount: refund["amount"]
                  }
                end
              end
            end
          end
        rescue StandardError => e
          # Log error but don't stop simulation
          puts "Error processing refund: #{e.message}" if @config&.log_level == Logger::DEBUG
        end

        # Return failure
        { error: "Failed to process refund" }
      end
    end
  end
end
