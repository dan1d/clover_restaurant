module CloverRestaurant
  module Simulator
    class EntitySetup
      SETUP_STEPS = [
        'tax_rates',
        'categories',
        'modifier_groups',
        'menu_items',
        'roles',
        'employees',
        'shifts'
      ]

      attr_reader :services_manager, :state, :logger

      def initialize(services_manager, state, logger)
        @services_manager = services_manager
        @state = state
        @logger = logger
      end

      def setup_entities(options = {})
        if options[:reset]
          @logger.info "Resetting all state..."
          @state.reset_all
        end

        if options[:resume]
          @logger.info "Resuming from last successful step..."
        end

        SETUP_STEPS.each do |step|
          process_setup_step(step)
        end
      end

      private

      def process_setup_step(step)
        return if @state.step_completed?(step)

        @logger.info "Processing setup step: #{step}"

        begin
          case step
          when 'tax_rates'
            setup_tax_rates
          when 'categories'
            setup_categories
          when 'modifier_groups'
            setup_modifier_groups
          when 'menu_items'
            setup_menu_items
          when 'roles'
            setup_roles
          when 'employees'
            setup_employees
          when 'shifts'
            setup_shifts
          end

          @state.mark_step_completed(step)
          @logger.info "✅ Successfully completed step: #{step}"
        rescue StandardError => e
          @logger.error "❌ Failed to complete step '#{step}': #{e.message}"
          raise
        end
      end

      def setup_tax_rates
        existing_rates = @services_manager.tax.get_tax_rates
        if existing_rates && existing_rates["elements"]&.any?
          @logger.info "Found #{existing_rates["elements"].size} existing tax rates"
          existing_rates["elements"].each do |rate|
            @state.record_entity('tax_rate', rate["id"], rate["name"], rate)
          end
          return
        end

        rates = @services_manager.tax.create_standard_tax_rates
        rates.each do |rate|
          @state.record_entity('tax_rate', rate["id"], rate["name"], rate)
        end
      end

      def setup_categories
        existing_categories = @services_manager.inventory.get_categories
        if existing_categories && existing_categories["elements"]&.any?
          @logger.info "Found #{existing_categories["elements"].size} existing categories"
          existing_categories["elements"].each do |category|
            @state.record_entity('category', category["id"], category["name"], category)
          end
          return
        end

        categories = @services_manager.inventory.create_standard_categories
        categories.each do |category|
          @state.record_entity('category', category["id"], category["name"], category)
        end
      end

      def setup_modifier_groups
        existing_groups = @services_manager.inventory.get_modifier_groups
        if existing_groups && existing_groups["elements"]&.any?
          @logger.info "Found #{existing_groups["elements"].size} existing modifier groups"
          existing_groups["elements"].each do |group|
            @state.record_entity('modifier_group', group["id"], group["name"], group)
          end
          return
        end

        groups = @services_manager.inventory.create_standard_modifier_groups
        groups.each do |group|
          @state.record_entity('modifier_group', group["id"], group["name"], group)
        end
      end

      def setup_menu_items
        categories = @state.get_entities('category')
        modifier_groups = @state.get_entities('modifier_group')

        items = @services_manager.inventory.create_sample_menu_items(categories)
        items.each do |item|
          @state.record_entity('menu_item', item["id"], item["name"], item)
        end
      end

      def setup_roles
        existing_roles = @services_manager.employee.get_roles
        if existing_roles && existing_roles["elements"]&.any?
          @logger.info "Found #{existing_roles["elements"].size} existing roles"
          existing_roles["elements"].each do |role|
            @state.record_entity('role', role["id"], role["name"], role)
          end
          return
        end

        roles = @services_manager.employee.create_standard_restaurant_roles
        roles.each do |role|
          @state.record_entity('role', role["id"], role["name"], role)
        end
      end

      def setup_employees
        roles = @state.get_entities('role')
        employees = @services_manager.employee.create_random_employees(15, roles)
        employees.each do |employee|
          @state.record_entity('employee', employee["id"], employee["name"], employee)
        end
      end

      def setup_shifts
        employees = @state.get_entities('employee')
        employees.each do |employee|
          shift = @services_manager.employee.clock_in(employee["clover_id"])
          @state.record_entity('shift', shift["id"], "#{employee["name"]}_shift", shift) if shift
        end
      end
    end
  end
end
