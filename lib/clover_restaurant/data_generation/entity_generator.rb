# lib/clover_restaurant/data_generation/entity_generator.rb
require_relative "base_generator"

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
          tax: ::CloverRestaurant::Services::TaxService.new(@config)
        }

        # Cache for entities to avoid redundant API calls
        @entity_cache = {}
      end

      # Fixed methods with correct parameter passing
      def create_inventory
        log_info("Checking for existing inventory...")
        existing_items = fetch_with_cache(:inventory_items) do
          services[:inventory].get_items(100)
        end

        existing_categories = fetch_with_cache(:inventory_categories) do
          services[:inventory].get_categories(100)
        end

        if existing_items && existing_items["elements"] && !existing_items["elements"].empty? &&
           existing_categories && existing_categories["elements"] && !existing_categories["elements"].empty?
          log_info("Found #{existing_items["elements"].size} existing inventory items and #{existing_categories["elements"].size} categories, skipping creation")
          {
            categories: existing_categories["elements"],
            items: existing_items["elements"]
          }
        else
          log_info("Creating inventory...")
          services[:inventory].create_random_restaurant_inventory(7, 15)
        end
      end

      def create_modifier_groups(items)
        log_info("Checking for existing modifier groups...")
        existing_groups = fetch_with_cache(:modifier_groups) do
          services[:modifier].get_modifier_groups(100)
        end

        if existing_groups && existing_groups["elements"] && existing_groups["elements"].size >= 5
          log_info("Found #{existing_groups["elements"].size} existing modifier groups, skipping creation")
          modifier_groups = existing_groups["elements"]
        else
          log_info("Creating modifier groups...")
          modifier_groups = services[:modifier].create_common_modifier_groups
        end

        # Skip checking item modifier groups since the endpoint is returning 405
        log_info("Skipping modifier assignment check due to API limitations")

        # Always assign modifiers since we can't reliably check if they're already assigned
        log_info("Assigning modifiers to items...")
        begin
          services[:modifier].assign_appropriate_modifiers_to_items(items)
        rescue StandardError => e
          log_error("Error assigning modifiers to items: #{e.message}, but continuing...")
        end

        modifier_groups
      end

      def create_tax_rates(categories)
        log_info("Checking for existing tax rates...")
        existing_tax_rates = fetch_with_cache(:tax_rates) do
          services[:tax].get_tax_rates(100)
        end

        if existing_tax_rates && existing_tax_rates["elements"] && !existing_tax_rates["elements"].empty?
          log_info("Found #{existing_tax_rates["elements"].size} existing tax rates, skipping creation")
          tax_rates = existing_tax_rates["elements"]
        else
          log_info("Creating tax rates...")
          tax_rates = services[:tax].create_standard_tax_rates
        end

        # Check if categories already have tax rates assigned
        log_info("Checking if tax rates need to be assigned to categories...")
        if categories.empty?
          log_info("No categories to assign tax rates to")
          return tax_rates
        end

        # Try to assign tax rates to categories anyway, as we can't reliably check
        begin
          log_info("Assigning tax rates to categories...")
          services[:tax].assign_category_tax_rates(categories, tax_rates)
        rescue StandardError => e
          log_error("Error assigning tax rates to categories: #{e.message}, but continuing...")
        end

        tax_rates
      end

      def create_discounts
        log_info("Checking for existing discounts...")
        existing_discounts = fetch_with_cache(:discounts) do
          services[:discount].get_discounts(100)
        end

        if existing_discounts && existing_discounts["elements"] && !existing_discounts["elements"].empty?
          log_info("Found #{existing_discounts["elements"].size} existing discounts, skipping creation")
          existing_discounts["elements"]
        else
          log_info("Creating discounts...")
          services[:discount].create_standard_discounts
        end
      end

      def create_employees_and_roles
        log_info("Checking for existing roles...")
        existing_roles = fetch_with_cache(:roles) do
          services[:employee].get_roles(100)
        end

        if existing_roles && existing_roles["elements"] && !existing_roles["elements"].empty?
          log_info("Found #{existing_roles["elements"].size} existing roles, skipping creation")
          roles = existing_roles["elements"]
        else
          log_info("Creating employee roles...")
          roles = services[:employee].create_standard_restaurant_roles
        end

        log_info("Checking for existing employees...")
        existing_employees = fetch_with_cache(:employees) do
          services[:employee].get_employees(100)
        end

        if existing_employees && existing_employees["elements"] && existing_employees["elements"].size >= 5
          log_info("Found #{existing_employees["elements"].size} existing employees, skipping creation")
          employees = existing_employees["elements"]
        else
          log_info("Creating employees...")
          employees = services[:employee].create_random_employees(15, roles)
        end

        [roles, employees]
      end

      def create_customers(count = 50)
        log_info("Checking for existing customers...")
        existing_customers = fetch_with_cache(:customers) do
          services[:customer].get_customers(100)
        end

        if existing_customers && existing_customers["elements"] && existing_customers["elements"].size >= count / 2
          log_info("Found #{existing_customers["elements"].size} existing customers, skipping creation")
          existing_customers["elements"]
        else
          log_info("Creating #{count} customers...")
          services[:customer].create_random_customers(count)
        end
      end

      def create_table_layout(name = "Main Restaurant")
        log_info("Checking for existing table layouts...")
        existing_floor_plans = fetch_with_cache(:floor_plans) do
          services[:table].get_floor_plans(100)
        end

        if existing_floor_plans && existing_floor_plans["elements"] &&
           existing_floor_plans["elements"].any? { |plan| plan["name"] == name }
          log_info("Found existing floor plan '#{name}', checking for tables")

          existing_tables = fetch_with_cache(:tables) do
            services[:table].get_tables(100)
          end

          if existing_tables && existing_tables["elements"] && !existing_tables["elements"].empty?
            log_info("Found #{existing_tables["elements"].size} existing tables, skipping creation")
            return {
              "floorPlan" => existing_floor_plans["elements"].find { |plan| plan["name"] == name },
              "tables" => existing_tables["elements"]
            }
          end
        end

        log_info("Creating table layout: #{name}")
        services[:table].create_standard_restaurant_layout(name)
      end

      def create_menus(categories, items)
        log_info("Checking for existing menus...")
        existing_menus = fetch_with_cache(:menus) do
          services[:menu].get_menus(100)
        end

        if existing_menus && existing_menus["elements"] && !existing_menus["elements"].empty?
          log_info("Found #{existing_menus["elements"].size} existing menus, skipping creation")
          existing_menus["elements"]
        else
          log_info("Creating menus...")
          standard_menu = services[:menu].create_standard_menu("Main Menu", categories, items)
          time_menus = services[:menu].create_time_based_menus(items)
          [standard_menu] + time_menus.compact
        end
      end

      private

      # Helper method to fetch with caching to reduce API calls
      def fetch_with_cache(key, &block)
        return @entity_cache[key] if @entity_cache.key?(key)

        begin
          result = block.call
          @entity_cache[key] = result if result
          result
        rescue StandardError => e
          log_error("Error fetching #{key}: #{e.message}")
          nil
        end
      end

      attr_reader :services
    end
  end
end
