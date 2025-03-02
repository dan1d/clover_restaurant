# lib/clover_restaurant/services/inventory_service.rb
module CloverRestaurant
  module Services
    class InventoryService < BaseService
      def get_categories(limit = 100, offset = 0)
        logger.info "Fetching categories for merchant #{@config.merchant_id}"
        make_request(:get, endpoint("categories"), nil, { limit: limit, offset: offset })
      end

      def get_category(category_id)
        logger.info "Fetching category #{category_id} for merchant #{@config.merchant_id}"
        make_request(:get, endpoint("categories/#{category_id}"))
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

        # Ensure item data has required fields and proper formatting
        data_to_send = item_data.dup

        # Make sure there's a price (required field)
        data_to_send["price"] ||= 0

        # Ensure price is an integer (cents)
        data_to_send["price"] = (data_to_send["price"] * 100).to_i if data_to_send["price"].is_a?(Float)

        # Add default fields if not provided
        data_to_send["cost"] ||= 0
        data_to_send["priceType"] ||= "FIXED"
        data_to_send["stockCount"] ||= nil # null means unlimited
        data_to_send["isRevenue"] = true unless data_to_send.key?("isRevenue")

        logger.info "Item data to send: #{data_to_send.inspect}"
        response = make_request(:post, endpoint("items"), data_to_send)

        if response && response["id"]
          logger.info "✅ Successfully created item '#{response["name"]}' with ID: #{response["id"]}"
        else
          logger.error "❌ ERROR: Item creation failed. Response: #{response.inspect}"
        end

        response
      end

      def update_item(item_id, item_data)
        logger.info "Updating item #{item_id} for merchant #{@config.merchant_id}"
        make_request(:post, endpoint("items/#{item_id}"), item_data)
      end

      def delete_item(item_id)
        logger.info "Deleting item #{item_id} for merchant #{@config.merchant_id}"
        make_request(:delete, endpoint("items/#{item_id}"))
      end

      def get_category_items(category_id, limit = 100, offset = 0)
        logger.info "Fetching items for category #{category_id}"
        make_request(:get, endpoint("categories/#{category_id}/items"), nil, { limit: limit, offset: offset })
      end

      # BULK OPERATIONS

      # Bulk update items using PUT to the /bulk_items endpoint
      def bulk_update_items(items_data)
        logger.info "Performing bulk update of #{items_data.size} items for merchant #{@config.merchant_id}"

        # Prepare the payload with the items array
        payload = {
          "items" => items_data
        }

        # Make the PUT request to the bulk_items endpoint
        # Note: This must be a PUT request, not POST
        make_request(:put, endpoint("bulk_items"), payload)
      end

      # This method specifically handles bulk category assignments
      # Fix for the bulk_assign_categories method in InventoryService
      def bulk_assign_categories(item_category_mapping)
        logger.info "Bulk assigning #{item_category_mapping.size} items to categories"

        # Get all items we need to update
        all_items = []

        # Use one API call to get all items
        items_response = get_items(500) # Get up to 500 items
        if items_response && items_response["elements"]
          all_items = items_response["elements"]
          logger.info "Retrieved #{all_items.size} items for category assignment"
        else
          logger.error "Failed to retrieve items for bulk assignment"
          return { success: false, updated_count: 0, assigned_count: 0, errors: ["Failed to retrieve items"] }
        end

        # Create a map of item IDs to item data for faster lookup
        item_map = {}
        all_items.each do |item|
          item_map[item["id"]] = item
        end

        # Prepare bulk update data
        bulk_items = []

        item_category_mapping.each do |item_id, category_id|
          # Look up the complete item in our map
          item = item_map[item_id]
          next unless item

          # Create a new item object with required fields
          update_item = {
            "id" => item_id
          }

          # Set categories field (completely replacing any existing categories)
          update_item["categories"] = [{ "id" => category_id }]

          # Copy essential fields from original item
          # These fields are required for a complete item update
          update_item["name"] = item["name"] if item["name"]
          update_item["price"] = item["price"] if item["price"]
          update_item["priceType"] = item["priceType"] if item["priceType"]
          update_item["hidden"] = item["hidden"] if item.key?("hidden")
          update_item["available"] = item["available"] if item.key?("available")
          update_item["defaultTaxRates"] = item["defaultTaxRates"] if item.key?("defaultTaxRates")
          update_item["cost"] = item["cost"] if item.key?("cost")
          update_item["isRevenue"] = item["isRevenue"] if item.key?("isRevenue")

          # Add to our bulk update array
          bulk_items << update_item
        end

        if bulk_items.empty?
          logger.warn "No items to update in bulk assignment"
          return { success: false, updated_count: 0, assigned_count: 0, errors: ["No items to update"] }
        end

        # Perform the bulk update with properly formatted items
        begin
          logger.info "Sending bulk update with #{bulk_items.size} items"
          response = bulk_update_items(bulk_items)

          # The response appears to be an array directly, not a hash with 'elements' key
          # This is likely where the error is occurring
          if response.is_a?(Array)
            successful_count = response.size
            logger.info "✅ Successfully updated #{successful_count} items with category assignments"
            {
              success: true,
              updated_count: successful_count,
              assigned_count: successful_count,
              errors: []
            }
          elsif response && response["elements"] && response["elements"].is_a?(Array)
            # As a fallback, also try the original format
            successful_count = response["elements"].size
            logger.info "✅ Successfully updated #{successful_count} items with category assignments"
            {
              success: true,
              updated_count: successful_count,
              assigned_count: successful_count,
              errors: []
            }
          else
            logger.error "❌ Bulk update failed: #{response.inspect}"
            {
              success: false,
              updated_count: 0,
              assigned_count: 0,
              errors: ["Bulk update failed: #{response.inspect}"]
            }
          end
        rescue StandardError => e
          logger.error "❌ Exception during bulk update: #{e.message}"
          logger.error e.backtrace.join("\n") if e.backtrace # Add stack trace for debugging
          {
            success: false,
            updated_count: 0,
            assigned_count: 0,
            errors: ["Exception during bulk update: #{e.message}"]
          }
        end
      end

      # Individual item-to-category assignment (fallback method)
      def assign_item_to_category(item_id, category_id)
        logger.info "Assigning item #{item_id} to category #{category_id}"

        # Get the current item data
        item = get_item(item_id)
        return nil unless item

        # Create the updated categories array
        categories_array = []

        # Include existing categories if any
        if item["categories"] && !item["categories"].empty?
          categories_array = item["categories"].map { |c| { "id" => c["id"] } }

          # Check if the item already has this category
          if item["categories"].any? { |c| c["id"] == category_id }
            logger.info "Item #{item_id} already assigned to category #{category_id}, skipping"
            return item
          end
        end

        # Add the new category
        categories_array << { "id" => category_id }

        # Prepare item data for update
        update_data = {
          "id" => item_id,
          "categories" => categories_array,
          "name" => item["name"],
          "price" => item["price"]
        }

        # Include other important fields
        update_data["priceType"] = item["priceType"] if item["priceType"]
        update_data["hidden"] = item["hidden"] if item.key?("hidden")
        update_data["available"] = item["available"] if item.key?("available")
        update_data["defaultTaxRates"] = item["defaultTaxRates"] if item.key?("defaultTaxRates")
        update_data["cost"] = item["cost"] if item.key?("cost")
        update_data["isRevenue"] = item["isRevenue"] if item.key?("isRevenue")

        # Use the bulk update endpoint with a single item (more reliable)
        bulk_response = bulk_update_items([update_data])

        if bulk_response && bulk_response["elements"] && bulk_response["elements"].any?
          logger.info "✅ Successfully assigned item #{item_id} to category #{category_id}"
          bulk_response["elements"].first
        else
          logger.warn "⚠️ Bulk update failed, falling back to direct update"
          update_item(item_id, { "categories" => categories_array })
        end
      end

      # Remove an item from a category
      def remove_item_from_category(item_id, category_id)
        logger.info "Removing item #{item_id} from category #{category_id}"

        # Get the current item data
        item = get_item(item_id)
        return nil unless item

        # Check if the item has categories
        return item unless item["categories"] && !item["categories"].empty?

        # Remove the specified category
        updated_categories = item["categories"].reject { |c| c["id"] == category_id }

        # If categories changed, update the item
        if updated_categories.length < item["categories"].length
          update_data = {
            "id" => item_id,
            "categories" => updated_categories,
            "name" => item["name"],
            "price" => item["price"]
          }

          # Include other important fields
          update_data["priceType"] = item["priceType"] if item["priceType"]
          update_data["hidden"] = item["hidden"] if item.key?("hidden")
          update_data["available"] = item["available"] if item.key?("available")
          update_data["defaultTaxRates"] = item["defaultTaxRates"] if item.key?("defaultTaxRates")
          update_data["cost"] = item["cost"] if item.key?("cost")
          update_data["isRevenue"] = item["isRevenue"] if item.key?("isRevenue")

          # Use bulk update for more reliable results
          bulk_response = bulk_update_items([update_data])

          if bulk_response && bulk_response["elements"] && bulk_response["elements"].any?
            logger.info "✅ Successfully removed item #{item_id} from category #{category_id}"
            bulk_response["elements"].first
          else
            logger.warn "⚠️ Bulk update failed, falling back to direct update"
            update_item(item_id, { "categories" => updated_categories })
          end
        else
          # No change needed
          item
        end
      end

      # Updated auto_assign_items_to_categories to use bulk_assign_categories
      def auto_assign_items_to_categories(items = nil, categories = nil)
        logger.info "Auto-assigning items to categories based on names"

        # Fetch items if not provided
        if items.nil?
          items_response = get_items
          items = items_response["elements"] if items_response && items_response["elements"]
        end

        # Fetch categories if not provided
        if categories.nil?
          categories_response = get_categories
          categories = categories_response["elements"] if categories_response && categories_response["elements"]
        end

        return false if items.nil? || items.empty? || categories.nil? || categories.empty?

        # Define common food categories and keywords
        category_keywords = {
          "appetizers" => ["appetizer", "starter", "small plate", "snack", "bread", "sticks", "dip", "salad"],
          "entrees" => %w[burger sandwich pasta steak chicken fish entree salmon alfredo],
          "sides" => %w[side fries rings potato vegetables salad],
          "desserts" => ["dessert", "sweet", "cake", "ice cream", "chocolate", "cheesecake"],
          "drinks" => %w[drink beverage soda water juice tea coffee],
          "alcoholic beverages" => %w[alcohol beer wine cocktail spirit],
          "specials" => %w[special chef signature house seasonal catch]
        }

        # Map items to categories
        item_category_mapping = {}

        # Create a category map for efficient lookups
        category_map = {}
        categories.each do |category|
          keyword = category["name"].downcase
          category_keywords.keys.each do |key|
            if keyword.include?(key)
              category_map[key] = category["id"]
              break
            end
          end

          # Also add a direct map by full category name
          category_map[category["name"].downcase] = category["id"]
        end

        # Find a default category (prefer "Specials" or similar)
        default_category_id = nil
        categories.each do |category|
          name = category["name"].downcase
          if name.include?("special") || name.include?("other") || name.include?("general")
            default_category_id = category["id"]
            break
          end
        end
        default_category_id ||= categories.first["id"] if categories.any?

        # Go through each item and find a matching category
        items.each do |item|
          # Skip items that already have categories
          next if item["categories"] && !item["categories"].empty?

          item_name = item["name"].downcase
          assigned = false

          # Check for keyword matches
          category_keywords.each do |category_key, keywords|
            next unless keywords.any? { |kw| item_name.include?(kw) }

            category_id = category_map[category_key]

            next unless category_id

            item_category_mapping[item["id"]] = category_id
            assigned = true
            break
          end

          # If no match, use default category
          item_category_mapping[item["id"]] = default_category_id if !assigned && default_category_id
        end

        if item_category_mapping.any?
          bulk_assign_categories(item_category_mapping)
          # Make sure we return the result properly

        else
          logger.info "No uncategorized items found"
          { success: true, updated_count: 0, assigned_count: 0, errors: [] }
        end
      end

      def assign_appropriate_modifiers_to_items(items)
        logger.info "Assigning appropriate modifiers to items"

        # Get all modifier groups
        all_groups = get_modifier_groups
        return false unless all_groups && all_groups["elements"]

        group_map = {}
        all_groups["elements"].each do |group|
          group_map[group["name"]] = group
        end

        # Create common groups if they don't exist
        if group_map.empty? || group_map.keys.length < 5
          created_groups = create_common_modifier_groups
          if created_groups && created_groups.is_a?(Array)
            created_groups.each do |group|
              group_map[group["name"]] = group if group && group["name"]
            end
          end
        end

        # Mapping for item names to appropriate modifier groups
        item_to_modifier_mapping = {
          "burger" => ["Temperature", "Add-ons", "Size Options"],
          "steak" => %w[Temperature Add-ons],
          "salad" => ["Dressing Options", "Protein Options"],
          "pizza" => ["Size Options", "Add-ons"],
          "pasta" => ["Protein Options", "Add-ons"],
          "sandwich" => ["Bread Options", "Add-ons"],
          "taco" => ["Protein Options", "Spice Level", "Add-ons"],
          "burrito" => ["Protein Options", "Spice Level", "Add-ons"],
          "soup" => ["Size Options", "Add-ons"],
          "breakfast" => %w[Temperature Add-ons],
          "appetizer" => ["Size Options", "Add-ons"],
          "dessert" => ["Size Options"],
          "coffee" => ["Size Options"],
          "tea" => ["Size Options"],
          "drink" => ["Size Options", "Add-ons"]
        }

        # Generic categories to apply if no specific match
        default_modifiers = ["Size Options", "Add-ons"]

        assigned_count = 0
        failed_count = 0

        items.each do |item|
          next unless item && item["name"] && item["id"]

          item_name = item["name"].downcase

          # Find appropriate modifier groups
          applicable_modifiers = []

          # Check for specific matches
          item_to_modifier_mapping.each do |key, modifiers|
            if item_name.include?(key)
              applicable_modifiers = modifiers
              break
            end
          end

          # Use default if no specific match
          applicable_modifiers = default_modifiers if applicable_modifiers.empty?

          # Add random modifiers (for variety)
          applicable_modifiers << "Spice Level" if rand < 0.3 && !applicable_modifiers.include?("Spice Level")

          # Assign modifier groups to item
          applicable_modifiers.each do |modifier_name|
            next unless group_map[modifier_name] && group_map[modifier_name]["id"]

            begin
              add_modifier_group_to_item(item["id"], group_map[modifier_name]["id"])
              assigned_count += 1
            rescue StandardError => e
              failed_count += 1
              logger.error "Error assigning modifier #{modifier_name} to item #{item["name"]}: #{e.message}"
            end
          end
        end

        logger.info "Assigned modifiers to #{assigned_count} items (failures: #{failed_count})"
        assigned_count > 0
      end

      # Method to check if items have category assignments
      def count_items_with_categories
        logger.info "Counting items with category assignments"

        items_response = get_items
        return 0 unless items_response && items_response["elements"]

        items = items_response["elements"]
        items_with_categories = items.count { |item| item["categories"] && !item["categories"].empty? }

        {
          total_items: items.size,
          items_with_categories: items_with_categories,
          percentage: items.size > 0 ? (items_with_categories.to_f / items.size * 100).round(2) : 0
        }
      end

      # Method to create sample menu items
      def create_sample_menu_items(categories = nil)
        logger.info "Creating sample menu items"

        # Get categories if not provided
        if categories.nil?
          categories_response = get_categories
          categories = categories_response["elements"] if categories_response && categories_response["elements"]
        end

        return false if categories.nil? || categories.empty?

        # Create a category map for easier lookup
        category_map = {}
        categories.each do |category|
          category_map[category["name"]] = category["id"]
        end

        # Define sample items by category
        sample_items = {
          "Appetizers" => [
            { "name" => "Caesar Salad", "price" => 995 },
            { "name" => "Garlic Bread", "price" => 595 },
            { "name" => "Mozzarella Sticks", "price" => 795 }
          ],
          "Entrees" => [
            { "name" => "Classic Burger", "price" => 1295 },
            { "name" => "Chicken Alfredo", "price" => 1495 },
            { "name" => "Grilled Salmon", "price" => 1695 }
          ],
          "Sides" => [
            { "name" => "French Fries", "price" => 495 },
            { "name" => "Onion Rings", "price" => 595 },
            { "name" => "Side Salad", "price" => 395 }
          ],
          "Desserts" => [
            { "name" => "Chocolate Cake", "price" => 795 },
            { "name" => "Cheesecake", "price" => 695 },
            { "name" => "Ice Cream", "price" => 495 }
          ],
          "Drinks" => [
            { "name" => "Soda", "price" => 295 },
            { "name" => "Iced Tea", "price" => 250 },
            { "name" => "Coffee", "price" => 345 }
          ],
          "Alcoholic Beverages" => [
            { "name" => "Craft Beer", "price" => 695 },
            { "name" => "House Wine", "price" => 895 },
            { "name" => "Cocktail", "price" => 995 }
          ],
          "Specials" => [
            { "name" => "Chef's Special", "price" => 1895 },
            { "name" => "Catch of the Day", "price" => 1795 },
            { "name" => "Seasonal Item", "price" => 1595 }
          ]
        }

        # Keep track of all created items
        all_created_items = []
        item_category_mapping = {}

        # First create all items
        sample_items.each do |category_name, items|
          category_id = category_map[category_name]
          next unless category_id

          logger.info "Creating items for category: #{category_name} (ID: #{category_id})"

          items.each do |item_data|
            # Create the item
            item_response = create_item(item_data)

            if item_response && item_response["id"]
              logger.info "Created item: #{item_response["name"]} (ID: #{item_response["id"]})"
              all_created_items << item_response

              # Build mapping for bulk update
              item_category_mapping[item_response["id"]] = category_id
            else
              logger.error "❌ Failed to create item: #{item_data["name"]}"
            end
          end
        end

        # Then bulk assign all items to their categories
        if item_category_mapping.any?
          logger.info "Bulk assigning #{item_category_mapping.size} new items to their categories..."
          result = bulk_assign_categories(item_category_mapping)

          if result && result[:success]
            logger.info "✅ Successfully assigned #{result[:updated_count]} items to categories"
          else
            logger.warn "⚠️ Bulk assignment had issues, falling back to individual assignments..."

            # Fall back to individual assignments if needed
            item_category_mapping.each do |item_id, category_id|
              assign_item_to_category(item_id, category_id)
            end
          end
        end

        logger.info "Successfully created #{all_created_items.size} sample menu items"
        all_created_items
      end
    end
  end
end
