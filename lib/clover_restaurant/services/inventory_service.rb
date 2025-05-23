module CloverRestaurant
  module Services
    class InventoryService < BaseService
      def create_category(category_data)
        logger.info "Creating new category for merchant #{@config.merchant_id}"

        # Check if category already exists
        existing_categories = get_categories
        if existing_categories && existing_categories["elements"]
          existing_category = existing_categories["elements"].find { |cat| cat["name"] == category_data["name"] }
          if existing_category
            logger.info "Category '#{category_data["name"]}' already exists with ID: #{existing_category["id"]}"
            return existing_category
          end
        end

        logger.info "Category data: #{category_data.inspect}"
        make_request(:post, endpoint("categories"), category_data)
      end

      def get_categories
        logger.info "Fetching categories for merchant #{@config.merchant_id}"
        make_request(:get, endpoint("categories"))
      end

      def create_standard_categories
        logger.info "=== Creating standard restaurant categories ==="

        standard_categories = [
          { name: "Appetizers", sortOrder: 1 },
          { name: "Entrees", sortOrder: 2 },
          { name: "Sides", sortOrder: 3 },
          { name: "Desserts", sortOrder: 4 },
          { name: "Drinks", sortOrder: 5 },
          { name: "Alcoholic Beverages", sortOrder: 6 },
          { name: "Specials", sortOrder: 7 }
        ]

        created_categories = []

        standard_categories.each do |category_data|
          begin
            category = create_category(category_data)
            if category && category["id"]
              logger.info "✅ Successfully created category: #{category["name"]}"
              created_categories << category
            else
              logger.error "❌ Failed to create category: #{category_data["name"]}"
            end
          rescue StandardError => e
            logger.error "❌ Error creating category #{category_data["name"]}: #{e.message}"
          end
        end

        created_categories
      end

      def create_sample_menu_items(categories = nil)
        logger.info "Creating menu items for all categories"

        # If no categories provided, fetch or create them
        unless categories && categories.any?
          existing_categories = get_categories
          if existing_categories && existing_categories["elements"] && existing_categories["elements"].any?
            categories = existing_categories["elements"]
            logger.info "Using #{categories.size} existing categories"
          else
            categories = create_standard_categories
            logger.info "Created #{categories.size} new standard categories"
          end
        end

        # Create or get modifier groups
        modifier_groups = get_modifier_groups
        if !modifier_groups || !modifier_groups["elements"] || modifier_groups["elements"].empty?
          logger.info "No modifier groups found, creating standard ones..."
          modifier_groups = { "elements" => create_standard_modifier_groups }
        else
          logger.info "Using existing modifier groups"
          modifier_groups = { "elements" => modifier_groups["elements"] }
        end

        created_items = []

        categories.each do |category|
          items = generate_items_for_category(category["name"])
          items.each do |item|
            # Ensure proper category association
            item_data = item.merge({
              "categories" => [{ "id" => category["id"] }],
              "category" => { "id" => category["id"] }
            })

            created_item = create_item(item_data)
            if created_item && created_item["id"]
              logger.info "✅ Created item '#{created_item["name"]}' in category '#{category["name"]}'"

              # Associate relevant modifier groups based on category and item
              relevant_groups = get_relevant_modifier_groups(
                category["name"],
                created_item["name"],
                modifier_groups["elements"]
              )

              relevant_groups.each do |group|
                begin
                  assign_modifier_group_to_item(created_item["id"], group["id"])
                  logger.info "  ✅ Assigned modifier group '#{group["name"]}' to item '#{created_item["name"]}'"
                rescue StandardError => e
                  logger.error "  ❌ Failed to assign modifier group '#{group["name"]}' to item '#{created_item["name"]}': #{e.message}"
                end
              end

              created_items << created_item
            else
              logger.error "❌ Failed to create item: #{item["name"]}"
            end
          end
        end

        created_items
      end

      def create_modifier_group(group_data)
        logger.info "Creating new modifier group for merchant #{@config.merchant_id}"

        # Check if modifier group already exists
        existing_groups = get_modifier_groups
        if existing_groups && existing_groups["elements"]
          existing_group = existing_groups["elements"].find { |g| g["name"] == group_data["name"] }
          if existing_group
            logger.info "Modifier group '#{group_data["name"]}' already exists with ID: #{existing_group["id"]}"
            return existing_group
          end
        end

        logger.info "Modifier group data: #{group_data.inspect}"
        make_request(:post, endpoint("modifier_groups"), group_data)
      end

      def get_modifier_groups
        logger.info "Fetching modifier groups for merchant #{@config.merchant_id}"
        make_request(:get, endpoint("modifier_groups"))
      end

      def create_modifier(group_id, modifier_data)
        logger.info "Creating new modifier in group #{group_id}"
        logger.info "Modifier data: #{modifier_data.inspect}"
        make_request(:post, endpoint("modifier_groups/#{group_id}/modifiers"), modifier_data)
      end

      def create_standard_modifier_groups
        logger.info "=== Creating standard modifier groups ==="

        standard_groups = [
          {
            name: "Temperature",
            showByDefault: true,
            modifiers: [
              { name: "Rare", price: 0 },
              { name: "Medium Rare", price: 0 },
              { name: "Medium", price: 0 },
              { name: "Medium Well", price: 0 },
              { name: "Well Done", price: 0 }
            ]
          },
          {
            name: "Add-ons",
            showByDefault: true,
            modifiers: [
              { name: "Extra Cheese", price: 150 },
              { name: "Bacon", price: 200 },
              { name: "Mushrooms", price: 150 },
              { name: "Caramelized Onions", price: 100 }
            ]
          },
          {
            name: "Sides Choice",
            showByDefault: true,
            modifiers: [
              { name: "French Fries", price: 0 },
              { name: "Sweet Potato Fries", price: 150 },
              { name: "Side Salad", price: 0 },
              { name: "Onion Rings", price: 200 }
            ]
          },
          {
            name: "Salad Dressings",
            showByDefault: true,
            modifiers: [
              { name: "Ranch", price: 0 },
              { name: "Blue Cheese", price: 0 },
              { name: "Balsamic Vinaigrette", price: 0 },
              { name: "Caesar", price: 0 }
            ]
          },
          {
            name: "Drink Size",
            showByDefault: true,
            modifiers: [
              { name: "Small", price: 0 },
              { name: "Medium", price: 100 },
              { name: "Large", price: 200 }
            ]
          }
        ]

        created_groups = []

        standard_groups.each do |group_data|
          begin
            # Extract modifiers before creating group
            modifiers = group_data.delete(:modifiers)

            # Create the modifier group
            group = create_modifier_group({
              "name" => group_data[:name],
              "showByDefault" => group_data[:showByDefault]
            })

            if group && group["id"]
              logger.info "✅ Created modifier group: #{group["name"]}"

              # Create modifiers within the group
              modifiers.each do |modifier_data|
                modifier = create_modifier(group["id"], {
                  "name" => modifier_data[:name],
                  "price" => modifier_data[:price]
                })

                if modifier && modifier["id"]
                  logger.info "  ✅ Created modifier: #{modifier["name"]}"
                else
                  logger.error "  ❌ Failed to create modifier: #{modifier_data[:name]}"
                end
              end

              created_groups << group
            else
              logger.error "❌ Failed to create modifier group: #{group_data[:name]}"
            end
          rescue StandardError => e
            logger.error "❌ Error creating modifier group #{group_data[:name]}: #{e.message}"
          end
        end

        created_groups
      end

      def assign_modifier_group_to_item(item_id, group_id)
        logger.info "Assigning modifier group #{group_id} to item #{item_id}"
        make_request(:post, endpoint("item_modifier_groups"), {
          "elements" => [
            {
              "modifierGroup" => { "id" => group_id },
              "item" => { "id" => item_id }
            }
          ]
        })
      end

      private

      def create_item(item_data)
        logger.info "Creating new item for merchant #{@config.merchant_id}"
        logger.info "Item data: #{item_data.inspect}"
        make_request(:post, endpoint("items"), item_data)
      end

      def generate_items_for_category(category_name)
        case category_name
        when "Appetizers"
          [
            { name: "Crispy Calamari", price: 1495, description: "Tender calamari lightly fried, served with marinara sauce", cost: 450 },
            { name: "Bruschetta", price: 995, description: "Grilled bread rubbed with garlic, topped with diced tomatoes, fresh basil, and olive oil", cost: 300 },
            { name: "Buffalo Wings", price: 1395, description: "Crispy chicken wings tossed in spicy buffalo sauce", cost: 420 }
          ]
        when "Entrees"
          [
            { name: "NY Strip Steak", price: 3295, description: "12oz USDA Prime NY Strip, served with roasted potatoes", cost: 990 },
            { name: "Grilled Salmon", price: 2695, description: "Fresh Atlantic salmon with lemon butter sauce", cost: 810 },
            { name: "Chicken Marsala", price: 2195, description: "Pan-seared chicken breast in marsala wine sauce", cost: 660 }
          ]
        when "Sides"
          [
            { name: "Garlic Mashed Potatoes", price: 595, description: "Creamy mashed potatoes with roasted garlic", cost: 180 },
            { name: "Grilled Asparagus", price: 695, description: "Fresh asparagus grilled with olive oil", cost: 210 },
            { name: "Mac and Cheese", price: 795, description: "Creamy four-cheese blend with toasted breadcrumbs", cost: 240 }
          ]
        when "Desserts"
          [
            { name: "New York Cheesecake", price: 895, description: "Classic NY style cheesecake with berry compote", cost: 270 },
            { name: "Chocolate Lava Cake", price: 995, description: "Warm chocolate cake with molten center", cost: 300 },
            { name: "Tiramisu", price: 795, description: "Classic Italian dessert with coffee and mascarpone", cost: 240 }
          ]
        when "Drinks"
          [
            { name: "Fresh Lemonade", price: 395, description: "House-made lemonade with fresh mint", cost: 120 },
            { name: "Iced Tea", price: 295, description: "Fresh brewed unsweetened iced tea", cost: 90 },
            { name: "Espresso", price: 395, description: "Double shot of Italian espresso", cost: 120 }
          ]
        when "Alcoholic Beverages"
          [
            { name: "House Red Wine", price: 895, description: "Glass of house Cabernet Sauvignon", cost: 270 },
            { name: "Craft Beer", price: 695, description: "Selection of local craft beers", cost: 210 },
            { name: "Classic Martini", price: 1195, description: "Gin or vodka martini with olive or twist", cost: 360 }
          ]
        when "Specials"
          [
            { name: "Chef's Daily Soup", price: 795, description: "Made fresh daily, ask server for details", cost: 240 },
            { name: "Catch of the Day", price: 2895, description: "Fresh seafood selection, ask server for details", cost: 870 },
            { name: "Seasonal Risotto", price: 2195, description: "Arborio rice with seasonal ingredients", cost: 660 }
          ]
        else
          []
        end
      end

      def get_relevant_modifier_groups(category_name, item_name, all_groups)
        # Helper method to find modifier groups by name
        find_groups = ->(names) {
          names.map { |name| all_groups.find { |g| g["name"] == name } }.compact
        }

        case category_name
        when "Entrees"
          if item_name.include?("Steak")
            find_groups.call(["Temperature", "Add-ons", "Sides Choice"])
          else
            find_groups.call(["Add-ons", "Sides Choice"])
          end
        when "Sides"
          find_groups.call(["Add-ons"])
        when "Drinks", "Alcoholic Beverages"
          find_groups.call(["Drink Size"])
        else
          []
        end
      end
    end
  end
end
