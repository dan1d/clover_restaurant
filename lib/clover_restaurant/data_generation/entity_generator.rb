# lib/clover_restaurant/data_generation/entity_generator.rb
module CloverRestaurant
  module DataGeneration
    class EntityGenerator
      attr_reader :config, :services_manager, :logger

      def initialize(config, services_manager)
        @config = config
        @services_manager = services_manager
        @logger = config.logger
      end

      def create_entities
        logger.info "=== Creating basic entities required for the restaurant system ==="

        # Step 1: Create standard categories
        logger.info "Step 1: Creating standard restaurant categories..."
        create_categories

        # Step 2: Create menu items
        logger.info "Step 2: Creating standard menu items..."
        create_items

        # Step 3: Create customer data
        logger.info "Step 3: Creating customer accounts..."
        create_customers

        # Step 4: Create employees
        logger.info "Step 4: Creating employee accounts..."
        create_employees

        # Step 5: Create modifiers
        logger.info "Step 5: Creating standard modifiers..."
        create_modifiers

        # Step 6: Create standard tenders
        logger.info "Step 6: Creating standard payment tenders..."
        create_tenders

        # Step 7: Create tax rates
        logger.info "Step 7: Setting up tax rates..."
        create_tax_rates

        # Step 8: Create standard discounts
        logger.info "Step 8: Creating standard discounts..."
        create_discounts

        logger.info "=== Finished creating all required entities ==="
      end

      def delete_all_entities
        logger.info "=== Deleting all entities for merchant #{config.merchant_id} ==="

        # This is a destructive operation that would remove all data
        # Implement with caution, starting with least dependent objects first

        # To be implemented as needed

        logger.info "=== Finished deleting all entities ==="
      end

      private

      def create_categories
        # Standard restaurant categories
        categories = [
          { "name" => "Appetizers", "sortOrder" => 1 },
          { "name" => "Entrees", "sortOrder" => 2 },
          { "name" => "Sides", "sortOrder" => 3 },
          { "name" => "Desserts", "sortOrder" => 4 },
          { "name" => "Drinks", "sortOrder" => 5 },
          { "name" => "Alcoholic Beverages", "sortOrder" => 6 },
          { "name" => "Specials", "sortOrder" => 7 }
        ]

        created_categories = []

        # Get existing categories first to avoid duplicates
        existing_categories = services_manager.inventory.get_categories

        if existing_categories && existing_categories["elements"] && !existing_categories["elements"].empty?
          logger.info "Found #{existing_categories["elements"].size} existing categories"

          # If we have at least 5 categories, consider it already set up
          if existing_categories["elements"].size >= 5
            logger.info "Sufficient categories already exist, skipping creation"
            return existing_categories["elements"]
          end

          # Otherwise, check which ones we need to create
          existing_names = existing_categories["elements"].map { |c| c["name"] }
          categories = categories.reject { |c| existing_names.include?(c["name"]) }
        end

        # Create any missing categories
        logger.info "Creating #{categories.size} new categories"

        categories.each do |category_data|
          category = services_manager.inventory.create_category(category_data)
          created_categories << category if category && category["id"]
        end

        created_categories
      end

      def create_items
        # Check for existing items
        existing_items = services_manager.inventory.get_items

        if existing_items && existing_items["elements"] && existing_items["elements"].size >= 15
          logger.info "Found #{existing_items["elements"].size} existing items, skipping creation"
          return existing_items["elements"]
        end

        # Get categories to assign items to
        categories = services_manager.inventory.get_categories

        unless categories && categories["elements"] && !categories["elements"].empty?
          logger.error "No categories available to assign items to"
          return []
        end

        # Create sample menu items in each category
        created_items = services_manager.inventory.create_sample_menu_items(categories["elements"])

        # Auto-assign modifiers to items if needed
        if created_items && !created_items.empty?
          services_manager.modifier.assign_appropriate_modifiers_to_items(created_items)
        end

        created_items
      end

      def create_customers
        # Check for existing customers
        existing_customers = services_manager.customer.get_customers

        if existing_customers && existing_customers["elements"] && existing_customers["elements"].size >= 10
          logger.info "Found #{existing_customers["elements"].size} existing customers, skipping creation"
          return existing_customers["elements"]
        end

        # Create random customers if needed
        services_manager.customer.create_random_customers(20)
      end

      def create_employees
        # Check for existing employees
        existing_employees = services_manager.employee.get_employees

        if existing_employees && existing_employees["elements"] && existing_employees["elements"].size >= 5
          logger.info "Found #{existing_employees["elements"].size} existing employees, skipping creation"
          return existing_employees["elements"]
        end

        # Create standard roles first
        roles = services_manager.employee.create_standard_restaurant_roles

        # Create employees with those roles
        services_manager.employee.create_random_employees(10, roles)
      end

      def create_modifiers
        # Check for existing modifier groups
        existing_modifier_groups = services_manager.modifier.get_modifier_groups

        if existing_modifier_groups && existing_modifier_groups["elements"] && existing_modifier_groups["elements"].size >= 5
          logger.info "Found #{existing_modifier_groups["elements"].size} existing modifier groups, skipping creation"
          return existing_modifier_groups["elements"]
        end

        # Create standard modifier groups
        services_manager.modifier.create_common_modifier_groups
      end

      def create_tenders
        # Check for existing tenders
        existing_tenders = services_manager.tender.get_tenders

        if existing_tenders && existing_tenders.size >= 3
          logger.info "Found #{existing_tenders.size} existing tenders, skipping creation"
          return existing_tenders
        end

        # Create standard tenders
        services_manager.tender.create_standard_tenders
      end

      def create_tax_rates
        # Check for existing tax rates
        existing_tax_rates = services_manager.tax.get_tax_rates

        if existing_tax_rates && existing_tax_rates["elements"] && existing_tax_rates["elements"].size >= 3
          logger.info "Found #{existing_tax_rates["elements"].size} existing tax rates, skipping creation"
          return existing_tax_rates["elements"]
        end

        # Create standard tax rates
        tax_rates = services_manager.tax.create_standard_tax_rates

        # Assign tax rates to categories
        if tax_rates && !tax_rates.empty?
          categories = services_manager.inventory.get_categories
          if categories && categories["elements"]
            services_manager.tax.assign_category_tax_rates(categories["elements"], tax_rates)
          end
        end

        tax_rates
      end

      def create_discounts
        # Check for existing discounts
        existing_discounts = services_manager.discount.get_discounts

        if existing_discounts && existing_discounts["elements"] && existing_discounts["elements"].size >= 5
          logger.info "Found #{existing_discounts["elements"].size} existing discounts, skipping creation"
          return existing_discounts["elements"]
        end

        # Create standard discounts
        services_manager.discount.create_standard_discounts
      end
    end
  end
end
