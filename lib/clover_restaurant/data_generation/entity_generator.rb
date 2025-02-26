# lib/clover_restaurant/services/data_generation/entity_generator.rb
require_relative "base_generator"
require_relative "../services/inventory_service"

module CloverRestaurant
  module DataGeneration
    class EntityGenerator < BaseGenerator
      def initialize(custom_config = nil)
        super(custom_config)

        # Initialize entity-related services with proper namespacing
        @services = {
          inventory: ::CloverRestaurant::Services::InventoryService.new(@config),
          modifier: ::CloverRestaurant::Services::ModifierService.new(@config),
          employee: ::CloverRestaurant::Services::EmployeeService.new(@config),
          customer: ::CloverRestaurant::Services::CustomerService.new(@config),
          table: ::CloverRestaurant::Services::TableService.new(@config),
          menu: ::CloverRestaurant::Services::MenuService.new(@config),
          discount: ::CloverRestaurant::Services::DiscountService.new(@config),
          tax: ::CloverRestaurant::Services::TaxRateService.new(@config)
        }
      end

      # Rest of the class remains the same
      def create_inventory
        log_info("Creating inventory...")
        services[:inventory].create_random_restaurant_inventory(7, 15)
      end

      def create_modifier_groups(items)
        log_info("Creating modifier groups...")
        modifier_groups = services[:modifier].create_common_modifier_groups
        services[:modifier].assign_appropriate_modifiers_to_items(items)
        modifier_groups
      end

      def create_tax_rates(categories)
        log_info("Creating tax rates...")
        tax_rates = services[:tax].create_standard_tax_rates
        services[:tax].assign_category_tax_rates(categories, tax_rates)
        tax_rates
      end

      def create_discounts
        log_info("Creating discounts...")
        services[:discount].create_standard_discounts
      end

      def create_employees_and_roles
        log_info("Creating employees and roles...")
        roles = services[:employee].create_standard_restaurant_roles
        employees = services[:employee].create_random_employees(15, roles)
        [roles, employees]
      end

      def create_customers(count = 50)
        log_info("Creating #{count} customers...")
        services[:customer].create_random_customers(count)
      end

      def create_table_layout(name = "Main Restaurant")
        log_info("Creating table layout: #{name}")
        services[:table].create_standard_restaurant_layout(name)
      end

      def create_menus(categories, items)
        log_info("Creating menus...")
        standard_menu = services[:menu].create_standard_menu("Main Menu", categories, items)
        time_menus = services[:menu].create_time_based_menus(items)
        [standard_menu] + time_menus
      end
    end
  end
end
