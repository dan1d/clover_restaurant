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

      def load_modifier_groups
        puts "=== Fetching modifier groups ==="
        modifier_groups_response = @services.with_cache(:modifier_groups) { @services.modifier.get_modifier_groups }

        if modifier_groups_response && modifier_groups_response["elements"]
          @data[:modifier_groups] = modifier_groups_response["elements"]
          puts "Loaded #{@data[:modifier_groups].size} modifier groups."
        else
          puts "No modifier groups found! 🚨"
          @data[:modifier_groups] = []
        end
      end

      def setup_restaurant(name = "Claude's Bistro")
        puts "=== Setting up restaurant: #{name} ==="

        load_inventory
        load_employees_and_roles
        load_tables
        load_modifier_groups
        load_tax_rates
        load_discounts # ✅ Ensure discounts are loaded

        puts "=== Fetching customers ==="
        customers_response = @services.with_cache(:customers) { @services.customer.get_customers }

        if customers_response && customers_response["elements"].any?
          @data[:customers] = customers_response["elements"]
          puts "Loaded #{@data[:customers].size} customers."
        else
          puts "No customers found. Creating test customers..."
          create_test_customers(5)
        end
      end

      def create_test_customers(count)
        created_customers = []

        count.times do |i|
          customer_data = {
            "firstName" => "TestCustomer#{i + 1}",
            "lastName" => "Demo",
            "email" => "testcustomer#{i + 1}@example.com"
          }

          begin
            response = @services.customer.create_customer(customer_data)
            if response && response["id"]
              created_customers << response
              puts "Successfully created test customer: #{response["firstName"]} #{response["lastName"]} (ID: #{response["id"]})"
            else
              puts "ERROR: Failed to create customer. Response: #{response.inspect}"
            end
          rescue StandardError => e
            puts "ERROR: Exception while creating customer: #{e.message}"
          end
        end

        # Store the created customers in @data[:customers]
        @data[:customers] = created_customers
      end

      def load_discounts
        puts "=== Fetching discounts ==="
        discounts_response = @services.with_cache(:discounts) { @services.discount.get_discounts }

        existing_discounts = discounts_response && discounts_response["elements"] ? discounts_response["elements"] : []
        @data[:discounts] = existing_discounts

        if existing_discounts.size >= 4
          puts "✅ Loaded #{existing_discounts.size} discounts."
          return
        else
          puts "🚨 Only found #{existing_discounts.size} discounts! Creating more..."
        end

        # Fixed required_discounts with proper format for the Clover API
        required_discounts = [
          { "name" => "Happy Hour", "amount" => -500 }, # $5 off (negative for discount)
          { "name" => "Loyalty Discount", "percentage" => 10 }, # 10% off
          { "name" => "Employee Discount", "percentage" => 20 }, # 20% off
          { "name" => "Holiday Special", "percentage" => 15 } # 15% off
        ]

        created_discounts = []

        required_discounts.each do |discount_data|
          existing = existing_discounts.find { |d| d["name"] == discount_data["name"] }
          if existing
            puts "✅ Discount '#{discount_data["name"]}' already exists, skipping."
            created_discounts << existing
            next
          end

          puts "Creating discount: #{discount_data.inspect}"
          response = @services.discount.create_discount(discount_data)

          if response && response["id"]
            puts "✅ Successfully created discount '#{response["name"]}' with ID: #{response["id"]}"
            created_discounts << response
          else
            puts "❌ ERROR: Failed to create discount '#{discount_data["name"]}'. Response: #{response.inspect}"
          end
        end

        @data[:discounts] += created_discounts
      end

      def load_tax_rates
        puts "=== Fetching tax rates ==="
        tax_rates_response = @services.with_cache(:tax_rates) { @services.tax.get_tax_rates }

        existing_tax_rates = tax_rates_response && tax_rates_response["elements"] ? tax_rates_response["elements"] : []
        @data[:tax_rates] = existing_tax_rates

        if existing_tax_rates.size >= 4
          puts "✅ Loaded #{existing_tax_rates.size} tax rates."
          return
        else
          puts "🚨 Only found #{existing_tax_rates.size} tax rates! Creating more..."
        end

        required_tax_rates = [
          { "name" => "Standard Tax", "rate" => 0.10 },  # 10%
          { "name" => "Reduced Tax", "rate" => 0.05 },   # 5%
          { "name" => "Food Tax", "rate" => 0.08 },      # 8%
          { "name" => "Alcohol Tax", "rate" => 0.15 }    # 15%
        ]

        created_tax_rates = []

        required_tax_rates.each do |tax_rate_data|
          existing = existing_tax_rates.find { |t| t["name"] == tax_rate_data["name"] }
          if existing
            puts "✅ Tax rate '#{tax_rate_data["name"]}' already exists, skipping."
            created_tax_rates << existing
            next
          end

          puts "Creating tax rate: #{tax_rate_data.inspect}"
          response = @services.tax.create_tax_rate(tax_rate_data)

          if response && response["id"]
            puts "✅ Successfully created tax rate '#{response["name"]}' with ID: #{response["id"]}"
            created_tax_rates << response
          else
            puts "❌ ERROR: Failed to create tax rate '#{tax_rate_data["name"]}'. Response: #{response.inspect}"
          end
        end

        @data[:tax_rates] += created_tax_rates
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

      def ensure_employees_exist
        puts "\nChecking restaurant employees...".colorize(:light_blue)

        employee_service = CloverRestaurant::Services::EmployeeService.new

        # First, ensure we have the necessary roles
        puts "Creating standard restaurant roles..."
        roles = employee_service.create_standard_restaurant_roles

        if roles && !roles.empty?
          puts "✅ Found #{roles.size} roles"
        else
          puts "❌ Failed to create roles, cannot create employees"
          return
        end

        # Check existing employees
        existing_employees = employee_service.get_employees
        employee_count = existing_employees && existing_employees["elements"] ? existing_employees["elements"].size : 0
        puts "Found #{employee_count} existing employees"

        # Only create more employees if we have fewer than 5
        if employee_count >= 5
          puts "✅ Sufficient employees exist (#{employee_count})"
          return
        end

        # Fixed employee data for predictable results
        employees_data = [
          { name: "John Manager", role_name: "Manager", pin: "1111" },
          { name: "Mary Server", role_name: "Server", pin: "2222" },
          { name: "Bob Bartender", role_name: "Bartender", pin: "3333" },
          { name: "Alice Host", role_name: "Host", pin: "4444" },
          { name: "Charlie Cook", role_name: "Kitchen Staff", pin: "5555" },
          { name: "David Manager", role_name: "Manager", pin: "6666" },
          { name: "Sarah Server", role_name: "Server", pin: "7777" },
          { name: "Jake Bartender", role_name: "Bartender", pin: "8888" },
          { name: "Emily Host", role_name: "Host", pin: "9999" },
          { name: "Mike Cook", role_name: "Kitchen Staff", pin: "1010" }
        ]

        # Find role IDs
        role_map = {}
        roles.each do |role|
          role_map[role["name"]] = role["id"]
        end

        created_employees = []

        employees_data.each_with_index do |emp_data, index|
          role_id = role_map[emp_data[:role_name]] || role_map.values.first # Default to first available role
          next unless role_id

          # Prepare employee data
          first_name, last_name = emp_data[:name].split(" ", 2)

          employee_data = {
            "name" => emp_data[:name],
            "nickname" => first_name,
            "customId" => "EMP#{index + 100}",
            "pin" => emp_data[:pin],
            "roles" => [{ "id" => role_id }],
            "inviteSent" => false,
            "isOwner" => false
          }

          puts "Creating employee: #{employee_data["name"]} (#{emp_data[:role_name]})"

          begin
            # Check if employee already exists by PIN
            existing_employee = employee_service.get_employee_by_pin(emp_data[:pin])

            if existing_employee
              puts "Employee with PIN #{emp_data[:pin]} already exists, skipping creation"
              created_employees << existing_employee
              next
            end

            employee = employee_service.create_employee(employee_data)

            if employee && employee["id"]
              puts "✅ Successfully created employee with ID: #{employee["id"]}"
              created_employees << employee
            else
              puts "❌ Error creating employee"
            end
          rescue StandardError => e
            puts "❌ Error creating employee: #{e.message}"
          end
        end

        puts "Created #{created_employees.size} new employees"
      end

      def load_inventory
        puts "=== Fetching inventory categories ==="
        categories_response = @services.with_cache(:categories) { @services.inventory.get_categories }
        if categories_response && categories_response["elements"]
          @data[:inventory][:categories] = categories_response["elements"]
          puts "Loaded #{@data[:inventory][:categories].size} categories."
        else
          puts "No categories found. Creating default categories..."
          @data[:inventory][:categories] = create_default_categories
        end

        puts "=== Fetching inventory items ==="
        items_response = @services.with_cache(:items) { @services.inventory.get_items }
        if items_response && items_response["elements"]
          @data[:inventory][:items] = items_response["elements"]
          puts "Loaded #{@data[:inventory][:items].size} items."

          # Check if items are already assigned to categories
          items_with_categories = 0
          @data[:inventory][:items].each do |item|
            items_with_categories += 1 if item["categories"] && !item["categories"].empty?
          end

          # If most items don't have categories, assign them
          if items_with_categories < @data[:inventory][:items].size * 0.8
            puts "Only #{items_with_categories} out of #{@data[:inventory][:items].size} items have categories. Auto-assigning items to categories..."
            assign_items_to_categories
          else
            puts "✅ Most items (#{items_with_categories} out of #{@data[:inventory][:items].size}) already have categories assigned."
          end
        else
          puts "No items found."
          @data[:inventory][:items] = []
        end
      rescue StandardError => e
        puts "Error loading inventory: #{e.message}"
        @data[:inventory][:categories] = []
        @data[:inventory][:items] = []
      end

      # Add these new helper methods
      def create_default_categories
        puts "Creating default restaurant categories..."

        default_categories = [
          { "name" => "Appetizers" },
          { "name" => "Entrees" },
          { "name" => "Sides" },
          { "name" => "Desserts" },
          { "name" => "Drinks" },
          { "name" => "Alcoholic Beverages" },
          { "name" => "Specials" }
        ]

        created_categories = []

        default_categories.each do |category_data|
          response = @services.inventory.create_category(category_data)

          if response && response["id"]
            created_categories << response
            puts "✅ Successfully created category: #{response["name"]} (ID: #{response["id"]})"
          else
            puts "❌ ERROR: Failed to create category. Response: #{response.inspect}"
          end
        end

        created_categories
      end

      def assign_items_to_categories
        puts "Assigning items to appropriate categories..."

        # Use the new auto-assign method from InventoryService
        result = @services.inventory.auto_assign_items_to_categories(
          @data[:inventory][:items],
          @data[:inventory][:categories]
        )

        if result && result[:success]
          puts "✅ Successfully assigned #{result[:assigned_count]} items to categories."
          if result[:errors].any?
            puts "⚠️ Some assignments had errors: #{result[:errors].length} errors."
            puts result[:errors].first(3).join("\n") if result[:errors].length > 0
          end
        else
          puts "❌ Failed to assign items to categories."
          puts result[:errors].join("\n") if result && result[:errors]
        end
      end

      def load_employees_and_roles
        # Load roles first
        @data[:roles] = @services.with_cache(:roles) { @services.employee.get_roles }
        @data[:roles] = if @data[:roles].is_a?(Hash) && @data[:roles]["elements"]
                          @data[:roles]["elements"]
                        else
                          []
                        end

        # Now load employees
        employees_data = @services.with_cache(:employees) { @services.employee.get_employees }
        @data[:employees] = employees_data
        @data[:employees] = if @data[:employees].is_a?(Hash) && @data[:employees]["elements"]
                              @data[:employees]["elements"]
                            else
                              []
                            end

        # If no employees found, create a fallback admin employee
        raise "here"
      rescue StandardError => e
        puts "Warning: Error loading employees: #{e.message}. Using fallback."
        puts e.backtrace
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

      def load_tables
        puts "=== Fetching tables ==="
        tables_response = @services.with_cache(:tables) { @services.table.get_tables }

        if tables_response && tables_response["elements"].any?
          @data[:tables] = tables_response["elements"]
          puts "Loaded #{@data[:tables].size} tables."
        else
          puts "No tables found. Creating fallback tables..."
          @data[:tables] = generate_fallback_tables
        end
      end

      def create_random_employees(count, roles)
        puts "Creating #{count} random employees..."

        created_employees = []

        count.times do |i|
          employee_data = {
            "name" => "Employee#{i + 1}",
            "nickname" => "Emp#{i + 1}",
            "customId" => "EMP#{100 + i}",
            "pin" => "#{1000 + i}", # Unique PIN
            "role" => roles.first["id"], # ✅ Fix: Send role ID directly
            "inviteSent" => false,
            "isOwner" => false
          }

          begin
            response = @services.employee.create_employee(employee_data)

            if response && response["id"]
              created_employees << response
              puts "✅ Successfully created employee: #{response["name"]} (ID: #{response["id"]})"
            else
              puts "❌ ERROR: Failed to create employee. Response: #{response.inspect}"
            end
          rescue StandardError => e
            puts "❌ ERROR: Exception while creating employee: #{e.message}"
          end
        end

        @data[:employees] += created_employees
      end

      def generate_fallback_tables
        puts "Generating fallback table data..."
        [
          { "id" => "TABLE1", "name" => "Table 1", "maxSeats" => 4 },
          { "id" => "TABLE2", "name" => "Table 2", "maxSeats" => 2 },
          { "id" => "TABLE3", "name" => "Table 3", "maxSeats" => 6 },
          { "id" => "TABLE4", "name" => "Table 4", "maxSeats" => 8 },
          { "id" => "TABLE5", "name" => "Table 5", "maxSeats" => 4 },
          { "id" => "BAR1", "name" => "Bar Seat 1", "maxSeats" => 1 },
          { "id" => "BAR2", "name" => "Bar Seat 2", "maxSeats" => 1 }
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

        @services.merchant.update_merchant_property("name", name)
      rescue StandardError => e
        puts "Warning: Could not update merchant name: #{e.message}"
      end

      def create_order(date, time, employee, customer)
        items = @data[:inventory][:items]
        discounts = @data[:discounts]

        return { error: "No items available" } if items.empty?

        item = items.sample
        total_price = item["price"]

        order_data = { "employee" => { "id" => employee["id"] }, "diningOption" => "HERE" }

        begin
          puts "DEBUG: Creating order for employee #{employee["id"]} with customer #{customer["id"]}"

          order = @services.order.create_order(order_data)

          return { error: "Failed to create order" } unless order && order["id"]

          puts "DEBUG: Order created successfully: #{order["id"]}"

          @services.order.add_customer_to_order(order["id"], customer["id"])
          @services.order.add_line_item(order["id"], item["id"], 1)
          total = item["price"]

          # Apply a discount with a 50% chance
          if discounts.any? && rand < 0.5
            discount = discounts.sample
            puts "Applying discount: #{discount["name"]}"
            @services.order.apply_discount(order["id"], discount["id"])
          end

          # Process payment
          payment = @services.payment.simulate_cash_payment(order["id"], total, { employee_id: employee["id"] })

          { order: order, total: total, payment: payment }
        rescue StandardError => e
          puts "ERROR: Exception when creating order: #{e.message}"
          { error: "Failed to create order" }
        end
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
