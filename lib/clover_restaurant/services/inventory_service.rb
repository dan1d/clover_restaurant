# lib/clover_restaurant/services/inventory_service.rb
module CloverRestaurant
  module Services
    class InventoryService < BaseService
      def get_items(limit = 100, offset = 0)
        logger.info "=== Fetching items for merchant #{@config.merchant_id} ==="
        make_request(:get, endpoint("items"), nil, { limit: limit, offset: offset })
      end

      def get_item(item_id)
        logger.info "=== Fetching item #{item_id} for merchant #{@config.merchant_id} ==="
        make_request(:get, endpoint("items/#{item_id}"))
      end

      def create_item(item_data)
        logger.info "=== Creating new item for merchant #{@config.merchant_id} ==="

        existing_items = get_items
        if existing_items.dig("elements")&.any? { |i| i["name"] == item_data["name"] }
          existing_item = existing_items["elements"].find { |i| i["name"] == item_data["name"] }
          logger.info "Item '#{item_data["name"]}' already exists with ID: #{existing_item["id"]}, skipping creation"
          return existing_item
        end

        logger.info "Item data: #{item_data.inspect}"
        make_request(:post, endpoint("items"), item_data)
      end

      def update_item(item_id, item_data)
        logger.info "=== Updating item #{item_id} for merchant #{@config.merchant_id} ==="
        make_request(:put, endpoint("items/#{item_id}"), item_data)
      end

      def delete_item(item_id)
        logger.info "=== Deleting item #{item_id} for merchant #{@config.merchant_id} ==="
        make_request(:delete, endpoint("items/#{item_id}"))
      end

      def get_categories(limit = 100, offset = 0)
        logger.info "=== Fetching categories for merchant #{@config.merchant_id} ==="
        make_request(:get, endpoint("categories"), nil, { limit: limit, offset: offset })
      end

      def get_category(category_id)
        logger.info "=== Fetching category #{category_id} for merchant #{@config.merchant_id} ==="
        make_request(:get, endpoint("categories/#{category_id}"))
      end

      def create_category(category_data)
        logger.info "=== Creating new category for merchant #{@config.merchant_id} ==="

        existing_categories = get_categories
        if existing_categories.dig("elements")&.any? { |c| c["name"] == category_data["name"] }
          existing_category = existing_categories["elements"].find { |c| c["name"] == category_data["name"] }
          logger.info "Category '#{category_data["name"]}' already exists with ID: #{existing_category["id"]}, skipping creation"
          return existing_category
        end

        logger.info "Category data: #{category_data.inspect}"
        make_request(:post, endpoint("categories"), category_data)
      end

      def update_category(category_id, category_data)
        logger.info "=== Updating category #{category_id} for merchant #{@config.merchant_id} ==="
        make_request(:put, endpoint("categories/#{category_id}"), category_data)
      end

      def delete_category(category_id)
        logger.info "=== Deleting category #{category_id} for merchant #{@config.merchant_id} ==="
        make_request(:delete, endpoint("categories/#{category_id}"))
      end

      def get_item_categories(item_id)
        logger.info "=== Fetching categories for item #{item_id} ==="
        make_request(:get, endpoint("items/#{item_id}/categories"))
      end

      def get_category_items(category_id)
        logger.info "=== Fetching items for category #{category_id} ==="
        make_request(:get, endpoint("categories/#{category_id}/items"))
      end

      def get_modifier_groups(limit = 100, offset = 0)
        logger.info "=== Fetching modifier groups for merchant #{@config.merchant_id} ==="
        make_request(:get, endpoint("modifier_groups"), nil, { limit: limit, offset: offset })
      end

      def get_modifiers(modifier_group_id)
        logger.info "=== Fetching modifiers for group #{modifier_group_id} ==="
        make_request(:get, endpoint("modifier_groups/#{modifier_group_id}/modifiers"))
      end

      def create_modifier(modifier_data)
        logger.info "=== Creating modifier using inventory service ==="

        if modifier_data.dig("modifierGroup", "id") && modifier_data["name"]
          group_id = modifier_data["modifierGroup"]["id"]
          existing_modifiers = get_modifiers(group_id)

          if existing_modifiers.dig("elements")&.any? { |m| m["name"] == modifier_data["name"] }
            existing_modifier = existing_modifiers["elements"].find { |m| m["name"] == modifier_data["name"] }
            logger.info "Modifier '#{modifier_data["name"]}' already exists in group #{group_id} with ID: #{existing_modifier["id"]}, skipping creation"
            return existing_modifier
          end
        end

        logger.info "Modifier data: #{modifier_data.inspect}"

        # Attempting two endpoints for modifier creation
        attempts = [
          ["modifiers", nil],
          ["modifier_groups/#{modifier_data.dig("modifierGroup", "id")}/modifiers",
           modifier_data.dig("modifierGroup", "id")]
        ]

        attempts.each do |endpoint_suffix, group_id|
          next if group_id.nil? && endpoint_suffix.include?("modifier_groups") # Skip second attempt if no group_id

          begin
            logger.info "Trying endpoint: #{endpoint_suffix}"
            return make_request(:post, endpoint(endpoint_suffix), modifier_data)
          rescue StandardError => e
            logger.error "Failed with endpoint #{endpoint_suffix}: #{e.message}"
          end
        end

        logger.error "All attempts to create modifier failed"
        raise "Failed to create modifier after trying multiple endpoint formats"
      end

      def add_item_to_category(item_id, category_id)
        logger.info "=== Adding item #{item_id} to category #{category_id} ==="

        item_categories = get_item_categories(item_id)
        if item_categories.dig("elements")&.any? { |ic| ic.dig("category", "id") == category_id }
          logger.info "Item #{item_id} is already in category #{category_id}, skipping"
          return item_categories["elements"].find { |ic| ic["category"]["id"] == category_id }
        end

        payload = { "item" => { "id" => item_id }, "category" => { "id" => category_id } }
        make_request(:post, endpoint("category_items"), payload)
      end

      # Method to create a complete restaurant inventory
      def create_random_restaurant_inventory(category_count = 7, items_per_category = 15)
        logger.info "=== Creating random restaurant inventory with #{category_count} categories and ~#{items_per_category} items per category ==="

        restaurant_categories = [
          { name: "Appetizers", display_name: "Appetizers" },
          { name: "Entrees", display_name: "Main Courses" },
          { name: "Sides", display_name: "Side Dishes" },
          { name: "Desserts", display_name: "Desserts" },
          { name: "Beverages", display_name: "Drinks" },
          { name: "Specials", display_name: "Chef's Specials" },
          { name: "Kids Menu", display_name: "Kids' Menu" },
          { name: "Breakfast", display_name: "Breakfast" },
          { name: "Lunch", display_name: "Lunch" },
          { name: "Dinner", display_name: "Dinner" }
        ]

        # Select a subset of categories based on category_count
        selected_categories = restaurant_categories.sample(category_count)

        created_categories = []
        created_items = []

        # Create the categories
        selected_categories.each do |category_data|
          category = create_category({
                                       "name" => category_data[:name],
                                       "sortOrder" => created_categories.size * 100
                                     })

          next unless category && category["id"]

          created_categories << category

          # Create items for this category
          item_count = items_per_category + rand(-3..3) # Add some variability

          generate_category_items(category["id"], item_count).each do |item_data|
            item = create_item(item_data)
            if item && item["id"]
              created_items << item
              add_item_to_category(item["id"], category["id"])
            end
          end
        end

        {
          categories: created_categories,
          items: created_items
        }
      end

      private

      def generate_category_items(category_id, count)
        # Different item templates based on category name
        category = get_category(category_id)
        category_name = category["name"] || ""

        case category_name.downcase
        when /appetizer/
          appetizer_items(count)
        when /entree/, /main/
          entree_items(count)
        when /side/
          side_items(count)
        when /dessert/
          dessert_items(count)
        when /beverage/, /drink/
          beverage_items(count)
        when /special/
          special_items(count)
        when /kid/
          kids_items(count)
        when /breakfast/
          breakfast_items(count)
        when /lunch/
          lunch_items(count)
        when /dinner/
          dinner_items(count)
        else
          generic_items(count)
        end
      end

      def appetizer_items(count)
        items = [
          { name: "Bruschetta", price: 795 },
          { name: "Nachos", price: 895 },
          { name: "Mozzarella Sticks", price: 695 },
          { name: "Buffalo Wings", price: 1095 },
          { name: "Calamari", price: 1195 },
          { name: "Spinach Artichoke Dip", price: 895 },
          { name: "Potato Skins", price: 795 },
          { name: "Chicken Quesadilla", price: 995 },
          { name: "Hummus Plate", price: 895 },
          { name: "Onion Rings", price: 595 },
          { name: "Shrimp Cocktail", price: 1395 },
          { name: "Stuffed Mushrooms", price: 895 },
          { name: "Charcuterie Board", price: 1595 },
          { name: "Garlic Bread", price: 495 },
          { name: "Fried Pickles", price: 695 }
        ]

        format_items(items.sample(count))
      end

      def entree_items(count)
        items = [
          { name: "Classic Burger", price: 1295 },
          { name: "Grilled Salmon", price: 1895 },
          { name: "Chicken Alfredo", price: 1595 },
          { name: "Ribeye Steak", price: 2495 },
          { name: "Vegetable Stir-Fry", price: 1395 },
          { name: "Fish & Chips", price: 1495 },
          { name: "Chicken Parmesan", price: 1695 },
          { name: "Shrimp Scampi", price: 1795 },
          { name: "BBQ Ribs", price: 1995 },
          { name: "Eggplant Parmesan", price: 1495 },
          { name: "Beef Stroganoff", price: 1695 },
          { name: "Lobster Ravioli", price: 2195 },
          { name: "Chicken Pot Pie", price: 1495 },
          { name: "Meatloaf", price: 1395 },
          { name: "Pork Chops", price: 1795 }
        ]

        format_items(items.sample(count))
      end

      def side_items(count)
        items = [
          { name: "French Fries", price: 395 },
          { name: "Sweet Potato Fries", price: 495 },
          { name: "Onion Rings", price: 495 },
          { name: "Side Salad", price: 595 },
          { name: "Mashed Potatoes", price: 395 },
          { name: "Rice Pilaf", price: 395 },
          { name: "Coleslaw", price: 295 },
          { name: "Steamed Vegetables", price: 495 },
          { name: "Mac & Cheese", price: 595 },
          { name: "Garlic Bread", price: 395 }
        ]

        format_items(items.sample(count))
      end

      def dessert_items(count)
        items = [
          { name: "Chocolate Cake", price: 795 },
          { name: "Cheesecake", price: 895 },
          { name: "Apple Pie", price: 695 },
          { name: "Ice Cream", price: 495 },
          { name: "Tiramisu", price: 895 },
          { name: "Crème Brûlée", price: 895 },
          { name: "Brownie Sundae", price: 795 },
          { name: "Key Lime Pie", price: 695 },
          { name: "Bread Pudding", price: 795 },
          { name: "Chocolate Mousse", price: 695 }
        ]

        format_items(items.sample(count))
      end

      def beverage_items(count)
        items = [
          { name: "Coffee", price: 295 },
          { name: "Iced Tea", price: 295 },
          { name: "Soda", price: 295 },
          { name: "Lemonade", price: 395 },
          { name: "Juice", price: 395 },
          { name: "Bottled Water", price: 195 },
          { name: "Milkshake", price: 595 },
          { name: "Smoothie", price: 695 },
          { name: "Hot Tea", price: 295 },
          { name: "Hot Chocolate", price: 395 }
        ]

        format_items(items.sample(count))
      end

      def special_items(count)
        items = [
          { name: "Chef's Special Pasta", price: 1895 },
          { name: "Catch of the Day", price: 2495 },
          { name: "Seasonal Risotto", price: 1795 },
          { name: "Surf and Turf", price: 2995 },
          { name: "Seasonal Vegetable Plate", price: 1595 },
          { name: "Special Curry", price: 1795 },
          { name: "Braised Short Ribs", price: 2195 },
          { name: "Seafood Paella", price: 2495 },
          { name: "Chef's Tasting Menu", price: 3995 },
          { name: "Weekly Special", price: 1995 }
        ]

        format_items(items.sample(count))
      end

      def kids_items(count)
        items = [
          { name: "Chicken Tenders", price: 695 },
          { name: "Mac & Cheese", price: 595 },
          { name: "Grilled Cheese", price: 595 },
          { name: "Mini Burgers", price: 695 },
          { name: "Spaghetti", price: 595 },
          { name: "Fish Sticks", price: 695 },
          { name: "PB&J Sandwich", price: 495 },
          { name: "Mini Pizza", price: 695 },
          { name: "Hot Dog", price: 595 },
          { name: "Cheese Quesadilla", price: 595 }
        ]

        format_items(items.sample(count))
      end

      def breakfast_items(count)
        items = [
          { name: "Eggs Benedict", price: 1295 },
          { name: "Pancakes", price: 995 },
          { name: "French Toast", price: 1095 },
          { name: "Breakfast Burrito", price: 1195 },
          { name: "Avocado Toast", price: 1095 },
          { name: "Breakfast Sandwich", price: 895 },
          { name: "Omelette", price: 1195 },
          { name: "Waffles", price: 1095 },
          { name: "Breakfast Platter", price: 1495 },
          { name: "Yogurt Parfait", price: 695 }
        ]

        format_items(items.sample(count))
      end

      def lunch_items(count)
        items = [
          { name: "Club Sandwich", price: 1295 },
          { name: "Caesar Salad", price: 1095 },
          { name: "Soup & Sandwich Combo", price: 1195 },
          { name: "Chicken Wrap", price: 1195 },
          { name: "Cobb Salad", price: 1295 },
          { name: "Turkey Panini", price: 1195 },
          { name: "Quiche of the Day", price: 1095 },
          { name: "Tuna Melt", price: 1095 },
          { name: "BBQ Chicken Sandwich", price: 1295 },
          { name: "Greek Salad", price: 1195 }
        ]

        format_items(items.sample(count))
      end

      def dinner_items(count)
        items = [
          { name: "NY Strip Steak", price: 2895 },
          { name: "Grilled Salmon", price: 2195 },
          { name: "Chicken Marsala", price: 1895 },
          { name: "Pork Tenderloin", price: 2095 },
          { name: "Seafood Pasta", price: 2395 },
          { name: "Vegetable Curry", price: 1795 },
          { name: "Prime Rib", price: 2995 },
          { name: "Duck Breast", price: 2495 },
          { name: "Lamb Chops", price: 2795 },
          { name: "Mushroom Risotto", price: 1695 }
        ]

        format_items(items.sample(count))
      end

      def generic_items(count)
        items = []
        count.times do |i|
          items << {
            name: "Item #{i + 1}",
            price: (rand(5..25) * 100) - 5 # $4.95 to $24.95
          }
        end
        format_items(items)
      end

      def format_items(items)
        items.map.with_index do |item, index|
          {
            "name" => item[:name],
            "price" => item[:price],
            "priceType" => "FIXED",
            "cost" => (item[:price] * 0.4).to_i, # 40% of price is cost
            "sku" => "SKU#{rand(1000..9999)}",
            "sortOrder" => index * 10
          }
        end
      end
    end
  end
end
