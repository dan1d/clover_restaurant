module CloverRestaurant
  module DataGeneration
    class EntityGenerator
      attr_reader :config, :services_manager

      def initialize(config, services_manager)
        @config = config
        @services_manager = services_manager
      end

      def create_categories
        logger.info "Creating restaurant categories"

        # Define standard restaurant categories
        categories = [
          "Appetizers",
          "Entrees",
          "Sides",
          "Desserts",
          "Drinks",
          "Alcoholic Beverages",
          "Specials"
        ]

        created_categories = []

        categories.each do |category_name|
          category_data = {
            "name" => category_name,
            "sortOrder" => categories.index(category_name)
          }

          created_category = @services_manager.inventory.create_category(category_data)
          if created_category && created_category["id"]
            logger.info "✅ Created category: #{created_category["name"]}"
            created_categories << created_category
          else
            logger.error "❌ Failed to create category: #{category_name}"
          end
        end

        created_categories
      end

      def create_items
        logger.info "Creating menu items"

        # Get all categories
        categories_response = @services_manager.inventory.get_categories
        return unless categories_response && categories_response["elements"]

        # Create sample menu items
        created_items = @services_manager.inventory.create_sample_menu_items(categories_response["elements"])

        if created_items && !created_items.empty?
          logger.info "✅ Created #{created_items.size} menu items"

          # Assign modifiers to items
          @services_manager.modifier.assign_appropriate_modifiers_to_items(created_items)
        else
          logger.error "❌ Failed to create menu items"
        end

        created_items
      end

      def delete_all_entities
        logger.info "Deleting all entities"

        # Delete categories and items
        @services_manager.inventory.delete_all_categories_and_items

        # Delete tax rates
        tax_rates = @services_manager.tax.get_tax_rates
        if tax_rates && tax_rates["elements"]
          tax_rates["elements"].each do |tax_rate|
            @services_manager.tax.delete_tax_rate(tax_rate["id"])
          end
        end

        # Delete modifier groups
        modifier_groups = @services_manager.modifier.get_modifier_groups
        if modifier_groups && modifier_groups["elements"]
          modifier_groups["elements"].each do |group|
            @services_manager.modifier.delete_modifier_group(group["id"])
          end
        end

        true
      end

      private

      def logger
        @logger ||= @config.logger
      end
    end
  end
end
