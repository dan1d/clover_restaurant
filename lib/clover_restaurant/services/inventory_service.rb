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

      def create_sample_menu_items(categories_from_state = nil)
        logger.info "Creating menu items and associating with categories"

        unless categories_from_state && categories_from_state.any?
          existing_categories_data = get_categories
          if existing_categories_data && existing_categories_data["elements"] && existing_categories_data["elements"].any?
            categories_from_state = existing_categories_data["elements"].map { |c| {"clover_id" => c["id"], "name" => c["name"]} }
            logger.info "Using #{categories_from_state.size} existing categories from API"
          else
            standard_category_objects = create_standard_categories
            categories_from_state = standard_category_objects.map { |c| {"clover_id" => c["id"], "name" => c["name"]} }
            logger.info "Created #{categories_from_state.size} new standard categories"
          end
        end

        modifier_groups_data = get_modifier_groups
        current_modifier_groups = if !modifier_groups_data || !modifier_groups_data["elements"] || modifier_groups_data["elements"].empty?
                                   logger.info "No modifier groups found, creating standard ones..."
                                   create_standard_modifier_groups
                                 else
                                   logger.info "Using existing modifier groups"
                                   modifier_groups_data["elements"]
                                 end

        all_created_items = []

        categories_from_state.each do |category_data|
          category_clover_id = category_data["clover_id"]
          category_name = category_data["name"]
          logger.info "Processing category: \'#{category_name}\' (ID: \'#{category_clover_id}\')"

          items_to_generate = generate_items_for_category(category_name)

          items_to_generate.each do |item_base_properties|
            # Prepare item payload for creation (without category association initially)
            item_payload = item_base_properties.transform_keys(&:to_s).merge({
              "defaultTaxRates" => true # Default value
              # No "categories" field here
            })

            logger.info "Attempting to create item '#{item_payload["name"]}'. Payload: #{item_payload.inspect}"
            created_item = create_item(item_payload)

            if created_item && created_item["id"]
              item_clover_id = created_item["id"]
              logger.info "✅ Successfully created item '#{created_item["name"]}' (ID: #{item_clover_id})"
              all_created_items << created_item

              # Now, associate the newly created item with its category using the new endpoint
              begin
                associate_item_with_category_via_category_items(item_clover_id, category_clover_id)
                logger.info "  ✅ Requested association for item '#{created_item["name"]}' with category '#{category_name}' (ID: '#{category_clover_id}') via category_items endpoint."
              rescue StandardError => e
                logger.error "  ❌ Failed to associate item '#{created_item["name"]}' with category '#{category_name}' via category_items: #{e.message}"
                logger.error "    Error details: #{e.backtrace.join("\n")}"
              end

              relevant_groups = get_relevant_modifier_groups(
                category_name,
                created_item["name"],
                current_modifier_groups
              )

              relevant_groups.each do |group|
                begin
                  assign_modifier_group_to_item(created_item["id"], group["id"])
                  logger.info "  ✅ Assigned modifier group '#{group["name"]}' to item '#{created_item["name"]}'"
                rescue StandardError => e
                  logger.error "  ❌ Failed to assign modifier group '#{group["name"]}' to item '#{created_item["name"]}': #{e.message}"
                end
              end
            else
              logger.error "❌ Failed to create item: #{item_base_properties[:name]}. API response: #{created_item.inspect}"
            end
          end
        end
        all_created_items
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

      # NEW METHOD using POST /v3/merchants/{mId}/category_items
      def associate_item_with_category_via_category_items(item_id, category_id)
        logger.info "Associating item ID '#{item_id}' with category ID '#{category_id}' using category_items endpoint."
        payload = {
          "elements" => [
            {
              "item" => { "id" => item_id },
              "category" => { "id" => category_id }
            }
          ]
        }
        # Using the endpoint: /v3/merchants/{mId}/category_items?delete=false
        make_request(:post, endpoint("category_items?delete=false"), payload)
      end
      # END OF NEW METHOD

      def get_modifier_groups_for_item(item_id)
        logger.info "Fetching item ID '#{item_id}' with expanded modifier groups."
        # MODIFIED: Fetch item with modifierGroups expansion
        item_response = make_request(:get, endpoint("items/#{item_id}?expand=modifierGroups"))

        unless item_response && item_response["modifierGroups"] && item_response["modifierGroups"]["elements"]
          logger.warn "No modifier groups found for item ID '#{item_id}' or error in response. Item response: #{item_response.inspect}"
          return []
        end

        associated_modifier_groups = item_response["modifierGroups"]["elements"]
        logger.info "Found #{associated_modifier_groups.size} modifier group(s) associated with item ID '#{item_id}'."

        detailed_modifier_groups = associated_modifier_groups.map do |group_ref|
          group_id = group_ref["id"]
          group_name = group_ref["name"] # Assuming name is part of the expanded group_ref

          logger.info "Fetching modifiers for group ID '#{group_id}' (Name: '#{group_name}', associated with item '#{item_id}')"
          modifiers_response = make_request(:get, endpoint("modifier_groups/#{group_id}/modifiers"))

          group_data_for_item = group_ref.dup # Start with the data from the expanded item's modifierGroups

          if modifiers_response && modifiers_response["elements"]
            group_data_for_item["modifiers"] = modifiers_response["elements"]
            logger.info "  Found #{modifiers_response["elements"].size} modifiers for group '#{group_name || group_id}'."
          else
            logger.warn "  No modifiers found for group ID '#{group_id}' or error in modifiers_response. Response: #{modifiers_response.inspect}"
            group_data_for_item["modifiers"] = []
          end
          group_data_for_item
        end

        detailed_modifier_groups
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
