module CloverRestaurant
  module Services
    class InventoryService < BaseService
      def get_items(limit = 100, offset = 0)
        logger.info "Fetching items for merchant #{@config.merchant_id}"
        make_request(:get, endpoint("items"), nil, { limit: limit, offset: offset })
      end

      def get_item(item_id)
        logger.info "Fetching item #{item_id} for merchant #{@config.merchant_id}"
        make_request(:get, endpoint("items/#{item_id}"))
      end

      def create_item(item_data)
        logger.info "Creating new item for merchant #{@config.merchant_id}"
        make_request(:post, endpoint("items"), item_data)
      end

      def update_item(item_id, item_data)
        logger.info "Updating item #{item_id} for merchant #{@config.merchant_id}"
        make_request(:post, endpoint("items/#{item_id}"), item_data)
      end

      def delete_item(item_id)
        logger.info "Deleting item #{item_id} for merchant #{@config.merchant_id}"
        make_request(:delete, endpoint("items/#{item_id}"))
      end

      def get_categories(limit = 100, offset = 0)
        logger.info "Fetching categories for merchant #{@config.merchant_id}"
        make_request(:get, endpoint("categories"), nil, { limit: limit, offset: offset })
      end

      def create_category(category_data)
        logger.info "Creating new category for merchant #{@config.merchant_id}"
        make_request(:post, endpoint("categories"), category_data)
      end

      def update_category(category_id, category_data)
        logger.info "Updating category #{category_id} for merchant #{@config.merchant_id}"
        make_request(:post, endpoint("categories/#{category_id}"), category_data)
      end

      def delete_category(category_id)
        logger.info "Deleting category #{category_id} for merchant #{@config.merchant_id}"
        make_request(:delete, endpoint("categories/#{category_id}"))
      end

      def add_item_to_category(item_id, category_id)
        logger.info "Adding item #{item_id} to category #{category_id}"
        make_request(:post, endpoint("category_items"), {
                       "item" => { "id" => item_id },
                       "category" => { "id" => category_id }
                     })
      end

      def get_modifier_groups(limit = 100, offset = 0)
        logger.info "Fetching modifier groups for merchant #{@config.merchant_id}"
        make_request(:get, endpoint("modifier_groups"), nil, { limit: limit, offset: offset })
      end

      def get_modifiers(modifier_group_id)
        logger.info "Fetching modifiers for group #{modifier_group_id}"
        make_request(:get, endpoint("modifier_groups/#{modifier_group_id}/modifiers"))
      end

      # Create a modifier method - this will be used instead of direct API call
      def create_modifier(modifier_data)
        logger.info "==== Creating modifier using inventory service ===="
        logger.info "Modifier data: #{modifier_data.inspect}"

        # Try two different endpoint formats to see which works

        # Method 1: Direct to modifiers endpoint (from ModifierService)
        begin
          logger.info "ATTEMPT 1: Using direct modifiers endpoint"
          result = make_request(:post, endpoint("modifiers"), modifier_data)
          logger.info "SUCCESS with direct modifiers endpoint"
          return result
        rescue StandardError => e
          logger.error "FAILED with direct modifiers endpoint: #{e.message}"
          logger.info "Trying alternative endpoint..."
        end

        # Method 2: Through modifier group endpoint
        begin
          if modifier_data["modifierGroup"] && modifier_data["modifierGroup"]["id"]
            group_id = modifier_data["modifierGroup"]["id"]
            logger.info "ATTEMPT 2: Using modifier_groups/#{group_id}/modifiers endpoint"
            result = make_request(:post, endpoint("modifier_groups/#{group_id}/modifiers"), modifier_data)
            logger.info "SUCCESS with modifier_groups/#{group_id}/modifiers endpoint"
            return result
          else
            logger.error "Cannot try alternative endpoint: No modifier group ID present in data"
          end
        rescue StandardError => e
          logger.error "FAILED with alternative endpoint too: #{e.message}"
        end

        # If we get here, both methods failed
        logger.error "All attempts to create modifier failed"
        raise "Failed to create modifier after trying multiple endpoint formats"
      end

      def create_random_restaurant_inventory(num_categories = 5, items_per_category = 10)
        logger.info "=== Creating random restaurant inventory with #{num_categories} categories and ~#{items_per_category} items per category ==="

        # Create food categories
        categories = []
        food_categories = %w[Appetizers Entrees Sides Desserts Drinks Specials Breakfast Lunch]

        num_categories.times do |i|
          category_name = food_categories[i % food_categories.length]
          category_data = {
            "name" => "#{category_name} #{i + 1}",
            "sortOrder" => i * 100
          }

          category = create_category(category_data)
          categories << category if category && category["id"]
        end

        logger.info "=== Created #{categories.size} categories ==="

        # Create items for each category
        items = []

        categories.each do |category|
          logger.info "=== Creating items for category: #{category["name"]} ==="

          items_per_category.times do |i|
            # Generate random food item based on category
            category_name = category["name"].split(" ").first
            item_name = generate_food_item_name(category_name)

            # Generate random price between $3.00 and $30.00
            price = rand(300..3000)

            item_data = {
              "name" => item_name,
              "price" => price,
              "priceType" => "FIXED",
              "defaultTaxRates" => true,
              "cost" => (price * rand(0.3..0.6)).to_i, # Cost at 30-60% of price
              "sku" => "SKU#{rand(100_000..999_999)}",
              "isRevenue" => true,
              "available" => true,
              "hidden" => false
            }

            item = create_item(item_data)
            next unless item && item["id"]

            items << item
            # Add item to category
            add_item_to_category(item["id"], category["id"])
          end
        end

        logger.info "=== Created #{items.size} items across all categories ==="

        # Create modifier groups and modifiers
        logger.info "=== Creating modifier groups and modifiers ==="
        modifier_groups = create_common_modifier_groups
        logger.info "=== Created #{modifier_groups.size} modifier groups ==="

        # Assign modifier groups to relevant items
        logger.info "=== Assigning modifier groups to items ==="
        assignment_count = 0

        items.each do |item|
          # Randomly assign 0-3 modifier groups to each item
          num_modifiers = rand(0..3)
          selected_modifiers = modifier_groups.sample(num_modifiers)

          selected_modifiers.each do |modifier_group|
            logger.info "=== Assigning modifier group #{modifier_group["name"]} to item #{item["name"]} ==="

            begin
              make_request(:post, endpoint("items/#{item["id"]}/modifier_groups"), {
                             "modifierGroup" => { "id" => modifier_group["id"] }
                           })
              assignment_count += 1
            rescue StandardError => e
              logger.error "Failed to assign modifier group: #{e.message}"
            end
          end
        end

        logger.info "=== Assigned modifier groups #{assignment_count} times ==="

        {
          categories: categories,
          items: items,
          modifier_groups: modifier_groups
        }
      end

      private

      def generate_food_item_name(category_type)
        case category_type
        when "Appetizers"
          "#{category_type} Special ##{rand(1..20)}"
        when "Entrees"
          "#{category_type} Special ##{rand(1..20)}"
        when "Sides"
          "Side Dish ##{rand(1..20)}"
        when "Desserts"
          "Dessert Special ##{rand(1..20)}"
        when "Drinks"
          "Signature Drink ##{rand(1..20)}"
        when "Specials"
          "Chef's Special ##{rand(1..20)}"
        when "Breakfast"
          "Breakfast Item ##{rand(1..20)}"
        when "Lunch"
          "Lunch Special ##{rand(1..20)}"
        else
          "Menu Item ##{rand(1..20)}"
        end
      end

      def create_common_modifier_groups
        logger.info "=== Creating common modifier groups ==="
        modifier_groups = []

        # Create common restaurant modifier groups
        groups_config = [
          {
            name: "Size Options",
            modifiers: [
              { name: "Small", price: 0 },
              { name: "Medium", price: 200 },
              { name: "Large", price: 400 }
            ]
          },
          {
            name: "Temperature",
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
            modifiers: [
              { name: "Extra Cheese", price: 150 },
              { name: "Bacon", price: 200 },
              { name: "Avocado", price: 250 },
              { name: "Mushrooms", price: 150 },
              { name: "Extra Sauce", price: 100 }
            ]
          },
          {
            name: "Dressing Options",
            modifiers: [
              { name: "Ranch", price: 0 },
              { name: "Italian", price: 0 },
              { name: "Balsamic Vinaigrette", price: 0 },
              { name: "Thousand Island", price: 0 },
              { name: "Blue Cheese", price: 0 }
            ]
          }
        ]

        groups_config.each_with_index do |group_config, group_index|
          logger.info "=== Creating modifier group #{group_index + 1}/#{groups_config.size}: #{group_config[:name]} ==="

          group_data = {
            "name" => group_config[:name],
            "selectionType" => group_config[:name] == "Add-ons" ? "MULTIPLE" : "SINGLE"
          }

          logger.info "Group data: #{group_data.inspect}"

          begin
            group = make_request(:post, endpoint("modifier_groups"), group_data)

            if group && group["id"]
              logger.info "Successfully created modifier group: #{group["name"]} with ID: #{group["id"]}"
              modifier_groups << group

              # Create modifiers for this group
              logger.info "=== Creating modifiers for group: #{group["name"]} ==="

              group_config[:modifiers].each_with_index do |modifier_config, index|
                modifier_data = {
                  "name" => modifier_config[:name],
                  "price" => modifier_config[:price],
                  "modifierGroup" => { "id" => group["id"] },
                  "sortOrder" => index * 10
                }

                logger.info "Creating modifier #{index + 1}/#{group_config[:modifiers].size}: #{modifier_config[:name]}"
                logger.info "Modifier data: #{modifier_data.inspect}"

                begin
                  create_modifier(modifier_data)
                  logger.info "Successfully created modifier: #{modifier_config[:name]}"
                rescue StandardError => e
                  logger.error "Failed to create modifier: #{e.message}"
                end
              end
            else
              logger.error "Failed to create modifier group - received invalid response: #{group.inspect}"
            end
          rescue StandardError => e
            logger.error "Failed to create modifier group: #{e.message}"
          end
        end

        logger.info "=== Finished creating modifier groups. Total created: #{modifier_groups.size} ==="
        modifier_groups
      end
    end
  end
end
