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

        # Load data safely with error handling for each section
        begin
          # Process inventory first
          load_inventory

          # Load modifier groups with error handling
          begin
            @data[:modifier_groups] = @services.with_cache(:modifier_groups) { @services.modifier.get_modifier_groups }
            if @data[:modifier_groups].is_a?(Hash) && @data[:modifier_groups]["elements"]
              @data[:modifier_groups] = @data[:modifier_groups]["elements"]
            end
          rescue StandardError => e
            puts "Warning: Error loading modifier groups: #{e.message}. Continuing with setup."
            @data[:modifier_groups] = []
          end

          # Load tax rates with error handling
          begin
            @data[:tax_rates] = @services.with_cache(:tax_rates) { @services.tax_rate.get_tax_rates }
            if @data[:tax_rates].is_a?(Hash) && @data[:tax_rates]["elements"]
              @data[:tax_rates] = @data[:tax_rates]["elements"]
            end
          rescue StandardError => e
            puts "Warning: Error loading tax rates: #{e.message}. Continuing with setup."
            @data[:tax_rates] = []
          end

          # Load discounts with error handling
          begin
            @data[:discounts] = @services.with_cache(:discounts) { @services.discount.get_discounts }
            if @data[:discounts].is_a?(Hash) && @data[:discounts]["elements"]
              @data[:discounts] = @data[:discounts]["elements"]
            end
          rescue StandardError => e
            puts "Warning: Error loading discounts: #{e.message}. Continuing with setup."
            @data[:discounts] = []
          end

          # Load employees and roles with error handling
          load_employees_and_roles

          # Load tables with error handling
          load_tables

          # Load customers with error handling
          begin
            customers_data = @services.with_cache(:customers) { @services.customer.get_customers }
            @data[:customers] = customers_data
            if @data[:customers].is_a?(Hash) && @data[:customers]["elements"]
              @data[:customers] = @data[:customers]["elements"]
            end
          rescue StandardError => e
            puts "Warning: Error loading customers: #{e.message}. Continuing with setup."
            @data[:customers] = []
          end
        rescue StandardError => e
          puts "Error during full setup: #{e.message}"
          puts "Continuing with partial data"
        end

        # Return the restaurant data, even if partially loaded
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

        # Simulate orders for the day with error handling
        begin
          simulate_orders_for_day(date, order_count, day_data)
        rescue StandardError => e
          puts "Error simulating orders for #{date}: #{e.message}"
          puts "Continuing with partial data"
        end

        # Cache and store the day's data
        @day_cache[date] = day_data
        @data[:days] << day_data

        day_data
      end

      private

      def load_inventory
        begin
          inventory_entities = @services.create_entities

          if inventory_entities
            # Get categories
            @data[:inventory][:categories] = @services.with_cache(:categories) { @services.inventory.get_categories }
            if @data[:inventory][:categories].is_a?(Hash) && @data[:inventory][:categories]["elements"]
              @data[:inventory][:categories] = @data[:inventory][:categories]["elements"]
            else
              @data[:inventory][:categories] = []
            end

            # Get items
            @data[:inventory][:items] = @services.with_cache(:items) { @services.inventory.get_items }
            if @data[:inventory][:items].is_a?(Hash) && @data[:inventory][:items]["elements"]
              @data[:inventory][:items] = @data[:inventory][:items]["elements"]
            else
              @data[:inventory][:items] = []
            end
          end
        rescue StandardError => e
          puts "Error loading inventory: #{e.message}. Continuing with setup."
          @data[:inventory][:categories] = []
          @data[:inventory][:items] = []
        end
      end

      def load_employees_and_roles
        begin
          # Load roles first
          @data[:roles] = @services.with_cache(:roles) { @services.employee.get_roles }
          if @data[:roles].is_a?(Hash) && @data[:roles]["elements"]
            @data[:roles] = @data[:roles]["elements"]
          else
            @data[:roles] = []
          end

          # Now load employees
          employees_data = @services.with_cache(:employees) { @services.employee.get_employees }
          @data[:employees] = employees_data
          if @data[:employees].is_a?(Hash) && @data[:employees]["elements"]
            @data[:employees] = @data[:employees]["elements"]
          else
            @data[:employees] = []
          end

          # If no employees found, create a fallback admin employee
          if @data[:employees].empty?
            puts "No employees found, using fallback employee data"
            @data[:employees] = [
              {
                "id" => "ADMIN_USER",
                "name" => "Test Admin",
                "role" => "ADMIN",
                "isOwner" => true
              }
            ]
          end
        rescue StandardError => e
          puts "Warning: Error loading employees: #{e.message}. Using fallback."
          # Create a fallback employee if loading fails
          @data[:employees] = [
            {
              "id" => "ADMIN_USER",
              "name" => "Test Admin",
              "role" => "ADMIN",
              "isOwner" => true
            }
          ]
          @data[:roles] = []
        end
      end

      def load_tables
        begin
          # Using POST to get tables since it seems GET is not allowed
          tables_data = @services.with_cache(:tables) do
            begin
              # Try to get tables through a workaround if the API supports it
              @services.table.get_tables
            rescue StandardError => e
              # Return empty array with elements if the endpoint fails
              puts "Warning: Error fetching tables, using fallback table data"
              { "elements" => generate_fallback_tables }
            end
          end

          @data[:tables] = tables_data
          if @data[:tables].is_a?(Hash) && @data[:tables]["elements"]
            @data[:tables] = @data[:tables]["elements"]
          else
            @data[:tables] = generate_fallback_tables
          end
        rescue StandardError => e
          puts "Warning: Error loading tables: #{e.message}. Using fallback."
          @data[:tables] = generate_fallback_tables
        end
      end

      def generate_fallback_tables
        puts "Generating fallback table data"
        # Create some fallback table data
        [
          {"id" => "TABLE1", "name" => "Table 1", "maxSeats" => 4},
          {"id" => "TABLE2", "name" => "Table 2", "maxSeats" => 2},
          {"id" => "TABLE3", "name" => "Table 3", "maxSeats" => 6},
          {"id" => "TABLE4", "name" => "Table 4", "maxSeats" => 8},
          {"id" => "TABLE5", "name" => "Table 5", "maxSeats" => 4},
          {"id" => "BAR1", "name" => "Bar Seat 1", "maxSeats" => 1},
          {"id" => "BAR2", "name" => "Bar Seat 2", "maxSeats" => 1}
        ]
      end

      def simulate_orders_for_day(date, order_count, day_data)
        order_count.times do |i|
          # Skip if we don't have required data
          next if @data[:inventory][:items].empty? || @data[:employees].empty? || @data[:customers].empty?

          # Create deterministic but varied order time
          hour = 8 + ((date.to_s.chars.map(&:ord).sum + i) % 14) # 8 AM to 10 PM
          minute = (date.to_s.chars.map(&:ord).sum + i) % 60
          order_time = Time.new(date.year, date.month, date.day, hour, minute)

          # Select employee deterministically
          employee_index = (date.to_s.chars.map(&:ord).sum + i) % @data[:employees].size
          employee = @data[:employees][employee_index]

          # Select customer deterministically
          customer_index = (date.to_s.chars.map(&:ord).sum + i * 3) % @data[:customers].size
          customer = @data[:customers][customer_index]

          # Create order with error handling
          begin
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
            next unless (date.to_s.chars.map(&:ord).sum + i) % 10 == 0

            begin
              refund_result = process_refund(order_result[:order], employee)

              if refund_result[:refund]
                day_data[:refunds] << refund_result[:refund]
                day_data[:total_refunds] += refund_result[:amount]
              end
            rescue StandardError => e
              puts "Error processing refund: #{e.message}"
            end
          rescue StandardError => e
            puts "Error creating order: #{e.message}"
          end
        end
      end

      def update_merchant_name(name)
        # Try to update the merchant name but don't fail if it doesn't work
        begin
          @services.merchant.update_merchant_property("name", name)
        rescue StandardError => e
          puts "Warning: Could not update merchant name: #{e.message}"
        end
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
            if order_seed % 10 < 3 && !@data[:discounts].empty?
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
