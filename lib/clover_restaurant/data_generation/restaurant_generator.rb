require_relative "base_generator"
require_relative "entity_generator"
require_relative "daily_operation_generator"
require_relative "analytics_generator"

module CloverRestaurant
  module DataGeneration
    class RestaurantGenerator < BaseGenerator
      attr_reader :data

      def initialize(custom_config = nil)
        super(custom_config)

        # Initialize specialized generators
        @entity_generator = EntityGenerator.new(@config)
        @daily_generator = DailyOperationGenerator.new(@config)
        @analytics_generator = AnalyticsGenerator.new(@config)

        # Initialize data storage
        @data = {
          inventory: { categories: [], items: [] },
          modifier_groups: [],
          tax_rates: [],
          discounts: [],
          roles: [],
          employees: [],
          customers: [],
          tables: [],
          menus: [],
          days: []
        }
      end

      def setup_restaurant(restaurant_name = "Clover Test Restaurant")
        log_info("Setting up restaurant: #{restaurant_name}")

        # Step 1: Create inventory
        inventory = @entity_generator.create_inventory
        data[:inventory][:categories] = inventory[:categories]
        data[:inventory][:items] = inventory[:items]

        # Step 2: Create modifier groups
        modifier_groups = @entity_generator.create_modifier_groups(data[:inventory][:items])
        data[:modifier_groups] = modifier_groups

        # Step 3: Create tax rates
        tax_rates = @entity_generator.create_tax_rates(data[:inventory][:categories])
        data[:tax_rates] = tax_rates

        # Step 4: Create standard discounts
        discounts = @entity_generator.create_discounts
        data[:discounts] = discounts

        # Step 5: Create employees and roles
        roles, employees = @entity_generator.create_employees_and_roles
        data[:roles] = roles
        data[:employees] = employees

        # Step 6: Create customers
        customers = @entity_generator.create_customers(50)
        data[:customers] = customers

        # Step 7: Create table layout
        layout = @entity_generator.create_table_layout("Main Restaurant")
        data[:tables] = layout[:tables]

        # Step 8: Create menus
        menus = @entity_generator.create_menus(data[:inventory][:categories], data[:inventory][:items])
        data[:menus] = menus

        log_info("Restaurant setup complete!")
        true
      end

      def simulate_business_day(date)
        log_info("Simulating business day: #{date}")

        # Initialize day data
        day_data = {
          date: date,
          employees_working: [],
          reservations: [],
          orders: [],
          payments: [],
          refunds: []
        }

        # 1. Schedule employees for the day
        day_data[:employees_working] = @daily_generator.schedule_employees_for_day(date, data[:employees])

        # 2. Create reservations for the day
        day_data[:reservations] = @daily_generator.create_reservations_for_day(date, data[:customers], data[:tables])

        # 3. Create walk-in orders (non-reservation orders)
        walk_in_orders = @daily_generator.create_walk_in_orders(
          date,
          rand(15..24),
          data[:employees],
          data[:customers],
          data[:tables],
          data[:inventory][:items],
          data[:discounts]
        )
        day_data[:orders] += walk_in_orders

        # 4. Create orders for reservations
        reservation_orders = @daily_generator.create_reservation_orders(
          date,
          day_data[:reservations],
          data[:employees],
          data[:inventory][:items]
        )
        day_data[:orders] += reservation_orders

        # 5. Process payments for orders
        day_data[:orders].each do |order|
          payment = @daily_generator.process_payment_for_order(order)
          day_data[:payments] << payment if payment
        end

        # 6. Process some refunds (about 5% of orders)
        refund_count = (day_data[:orders].size * 0.05).round
        day_data[:refunds] = @daily_generator.process_random_refunds(day_data[:orders], refund_count)

        # Store the day data
        data[:days] << day_data

        log_info("Day simulation complete: #{day_data[:orders].size} orders, #{day_data[:payments].size} payments, #{day_data[:refunds].size} refunds")
        day_data
      end

      def simulate_business_period(start_date, days)
        log_info("Simulating #{days} days of business starting from #{start_date}")

        # Setup restaurant first if not already set up
        setup_restaurant if data[:inventory][:items].empty?

        # Simulate each day
        results = []
        days.times do |i|
          current_date = start_date + i
          day_result = simulate_business_day(current_date)
          results << day_result
        end

        # Generate summary
        summary = @analytics_generator.generate_period_summary(data[:days], start_date, days)

        log_info("Business period simulation complete: #{results.size} days")
        { days: results, summary: summary }
      end

      private

      def log_info(message)
        logger.info(message)
      end

      def log_error(message)
        logger.error(message)
      end
    end
  end
end
