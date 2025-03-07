# lib/clover_restaurant/services/inventory_service.rb
module CloverRestaurant
  module Services
    class InventoryService < BaseService
      def get_categories(limit = 100, offset = 0)
        logger.info "Fetching categories for merchant #{@config.merchant_id}"
        make_request(:get, endpoint("categories"), nil, { limit: limit, offset: offset, expand: "items" })
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

      def delete_all_categories_and_items
        logger.info "Deleting all categories and items for merchant #{@config.merchant_id}"

        # First get all categories
        categories_response = get_categories
        return false unless categories_response && categories_response["elements"]

        # Delete each category and its items
        categories_response["elements"].each do |category|
          category_id = category
          delete_category(category_id)
        end

        # now delete all items
        items_response = get_items
        return false unless items_response && items_response["elements"]

        items_response["elements"].each do |item|
          item_id = item["id"]
          delete_item(item_id)
        end

        true
      end

      def get_items(limit = 100, offset = 0)
        logger.info "Fetching items for merchant #{@config.merchant_id}"
        make_request(:get, endpoint("items"), nil, { limit: limit, offset: offset, expand: "categories" })
      end

      def get_item(item_id)
        logger.info "Fetching item #{item_id} for merchant #{@config.merchant_id}"
        make_request(:get, endpoint("items/#{item_id}"), nil, { expand: "categories" })
      end

      def create_item(item_data)
        logger.info "Creating new item for merchant #{@config.merchant_id}"

        # Ensure item data has required fields and proper formatting
        data_to_send = item_data.dup

        # Make sure there's a price (required field)
        data_to_send["price"] ||= rand(500..2000) # Random price between $5 and $20

        # Ensure price is an integer (cents)
        data_to_send["price"] = (data_to_send["price"] * 100).to_i if data_to_send["price"].is_a?(Float)

        # Add default fields if not provided
        data_to_send["cost"] ||= rand(100..500) # Random cost between $1 and $5
        data_to_send["priceType"] ||= "FIXED"
        data_to_send["stockCount"] ||= nil # null means unlimited
        data_to_send["isRevenue"] = true unless data_to_send.key?("isRevenue")

        # Include categories if provided
        data_to_send["categories"] = item_data["categories"] if item_data["categories"]
        # byebug if item_data["categories"]
        logger.info "Item data to send: #{data_to_send.inspect}"
        response = make_request(:post, endpoint("items"), data_to_send, { expand: "categories" })

        if response && response["id"]
          logger.info "✅ Successfully created item '#{response["name"]}' with ID: #{response["id"]}"
        else
          logger.error "❌ ERROR: Item creation failed. Response: #{response.inspect}"
        end

        response
      end

      def update_item(item_id, item_data)
        logger.info "Updating item #{item_id} for merchant #{@config.merchant_id}"

        # Prepare the payload
        payload = item_data.dup

        # Ensure required fields are included
        payload["id"] = item_id

        logger.info "Update payload: #{payload.inspect}"
        make_request(:put, endpoint("items/#{item_id}"), payload, { expand: "categories" })
      end

      def delete_item(item_id)
        logger.info "Deleting item #{item_id} for merchant #{@config.merchant_id}"
        make_request(:delete, endpoint("items/#{item_id}"))
      end

      def get_category_items(category_id, limit = 100, offset = 0)
        logger.info "Fetching items for category #{category_id}"
        make_request(:get, endpoint("categories/#{category_id}/items"), nil, { limit: limit, offset: offset })
      end

      def bulk_update_items(items_data)
        logger.info "Performing bulk update of #{items_data.size} items for merchant #{@config.merchant_id}"

        # Prepare the payload with the items array
        payload = {
          "items" => items_data
        }

        # Make the PUT request to the bulk_items endpoint
        response = make_request(:put, endpoint("bulk_items"), payload)

        if response.is_a?(Array)
          # Wrap the array in a hash to match the expected format
          { "elements" => response }
        else
          response
        end
      end

      # Individual item-to-category assignment (fallback method)
      def assign_item_to_category(item_id, category)
        log_info("🔄 Assigning item #{item_id} to category #{category}...")

        # Get the current item data
        item = get_item(item_id)
        unless item
          log_error("❌ Item #{item_id} not found, skipping")
          return nil
        end

        # Get the category data
        category = get_category(category["id"])
        unless category
          log_error("❌ Category #{category["id"]} not found, skipping")
          return nil
        end

        # Prepare the payload for assigning the category
        payload = {
          "elements" => [
            {
              "category" => { "id" => category["id"] },
              "item" => { "id" => item_id }
            }
          ]
        }

        # Update the item with the new category
        updated_item = make_request(:post, endpoint("category_items"), payload, { expand: "categories" })
        if updated_item && updated_item["id"]
          log_info("✅ Successfully assigned item #{item_id} to category #{category["name"]}")
          updated_item
        else
          log_error("❌ Failed to assign item #{item_id} to category #{category["name"]}")
          nil
        end
      end

      # Add this method to your InventoryService class in lib/clover_restaurant/services/inventory_service.rb

      def bulk_assign_items_to_categories(item_category_mapping)
        logger.info "=== Performing bulk assignment of #{item_category_mapping.size} items to categories ==="

        success_count = 0
        error_count = 0
        errors = []

        # Process items in batches to avoid overwhelming the API
        batch_size = 10
        item_category_mapping.each_slice(batch_size) do |batch|
          batch.each do |item_id, category_id|
            # Get current item to check existing categories
            item = get_item(item_id)

            unless item
              logger.error "Item #{item_id} not found"
              errors << "Item #{item_id} not found"
              error_count += 1
              next
            end

            # Check if item already has this category
            if item["categories"] &&
               item["categories"]["elements"] &&
               item["categories"]["elements"].any? { |cat| cat["id"] == category_id }
              logger.info "Item #{item_id} already has category #{category_id}, skipping"
              success_count += 1
              next
            end

            # Prepare the payload for assigning the category
            payload = {
              "elements" => [
                {
                  "category" => { "id" => category_id },
                  "item" => { "id" => item_id }
                }
              ]
            }

            # Make the request to assign category
            response = make_request(:post, endpoint("category_items"), payload)

            if response && (response["elements"] || response.is_a?(Array))
              logger.info "✅ Successfully assigned item #{item_id} to category #{category_id}"
              success_count += 1
            else
              logger.error "❌ Failed to assign item #{item_id} to category #{category_id}"
              errors << "Failed to assign item #{item_id} to category #{category_id}"
              error_count += 1
            end
          rescue StandardError => e
            logger.error "Error assigning item #{item_id} to category #{category_id}: #{e.message}"
            errors << "Error: #{e.message}"
            error_count += 1
          end
        end

        logger.info "=== Bulk assignment completed: #{success_count} successful, #{error_count} failed ==="

        {
          success: error_count == 0,
          updated_count: success_count,
          error_count: error_count,
          errors: errors
        }
      end

      # Alternative implementation using bulk_update_items method
      # Add this method to your InventoryService class in lib/clover_restaurant/services/inventory_service.rb

      # Fixed version of auto_assign_items_to_categories for InventoryService

      def auto_assign_items_to_categories(items = nil, categories = nil)
        logger.info "=== Auto-assigning items to categories based on names ==="

        # Fetch items if not provided
        if items.nil? || items.empty?
          items_response = get_items
          items = items_response["elements"] if items_response && items_response["elements"]
        end

        # Fetch categories if not provided
        if categories.nil? || categories.empty?
          categories_response = get_categories
          categories = categories_response["elements"] if categories_response && categories_response["elements"]
        end

        if items.nil? || items.empty? || categories.nil? || categories.empty?
          return { success: false, assigned_count: 0,
                   errors: ["No items or categories available"] }
        end

        # Define common food categories and keywords
        category_keywords = {
          "appetizers" => ["appetizer", "starter", "small plate", "snack", "bread", "sticks", "dip", "salad",
                           "soup"],
          "entrees" => %w[burger sandwich pasta steak chicken fish entree salmon alfredo pizza main dish dinner],
          "sides" => %w[side fries rings potato vegetables rice beans chips],
          "desserts" => ["dessert", "sweet", "cake", "ice cream", "chocolate", "cheesecake", "pie", "cookie"],
          "drinks" => %w[drink beverage soda water juice tea coffee cola lemonade],
          "alcoholic beverages" => %w[alcohol beer wine cocktail spirit whiskey vodka gin rum tequila],
          "specials" => %w[special chef signature house seasonal catch featured]
        }

        # Map for storing item to category assignments
        item_category_mapping = {}
        errors = []
        already_assigned_count = 0
        unmatched_items = []

        # Create a category map for efficient lookups
        category_map = {}
        categories.each do |category|
          category_name = category["name"].downcase

          # Map by exact name
          category_map[category_name] = category["id"]

          # Also map by keyword matches
          category_keywords.each do |key, keywords|
            if keywords.any? { |keyword| category_name.include?(keyword) } || category_name.include?(key)
              category_map[key] = category["id"]
            end
          end
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

        logger.info "Checking #{items.size} items for category assignment"

        # Go through each item and find a matching category
        items.each do |item|
          # Check if item already has categories
          # CRITICAL FIX: The structure appears different in the API response
          has_categories = false

          # Check different ways categories might be represented in the item data
          if item["categories"] && item["categories"].is_a?(Hash) && item["categories"]["elements"] && !item["categories"]["elements"].empty?
            has_categories = true
          elsif item["categories"] && item["categories"].is_a?(Array) && !item["categories"].empty?
            has_categories = true
          end

          if has_categories
            logger.info "Item #{item["name"]} already has categories, skipping"
            already_assigned_count += 1
            next
          end

          logger.info "Processing uncategorized item: #{item["name"]}"
          item_name = item["name"].downcase
          assigned = false

          # Check for keyword matches
          category_keywords.each do |category_key, keywords|
            next unless keywords.any? { |kw| item_name.include?(kw) } || item_name.include?(category_key)

            category_id = category_map[category_key]

            next unless category_id

            logger.info "Matched item '#{item["name"]}' to category key '#{category_key}'"
            item_category_mapping[item["id"]] = category_id
            assigned = true
            break
          end

          # If no match, use default category
          unless assigned
            if default_category_id
              logger.info "Using default category for '#{item["name"]}'"
              item_category_mapping[item["id"]] = default_category_id
            else
              logger.warn "No matching category or default for '#{item["name"]}'"
              unmatched_items << item["name"]
            end
          end
        end

        # Log unmatched items
        if unmatched_items.any?
          logger.warn "#{unmatched_items.size} items couldn't be matched to any category and no default was available:"
          unmatched_items.each { |name| logger.warn "  - #{name}" }
        end

        # Use assignment if we have items to assign
        if item_category_mapping.any?
          logger.info "=== Bulk assigning #{item_category_mapping.size} items to categories ==="

          # Log the assignments for debugging
          item_category_mapping.each do |item_id, category_id|
            item_name = items.find { |i| i["id"] == item_id }&.fetch("name", "Unknown")
            category_name = categories.find { |c| c["id"] == category_id }&.fetch("name", "Unknown")
            logger.info "Mapping: #{item_name} -> #{category_name}"
          end

          result = bulk_assign_categories(item_category_mapping)

          result[:already_assigned_count] = already_assigned_count
          result
        else
          logger.info "No uncategorized items found or all items already matched with categories"
          {
            success: true,
            updated_count: 0,
            assigned_count: 0,
            already_assigned_count: already_assigned_count,
            errors: []
          }
        end
      end

      # Fixed bulk_assign_categories method
      def bulk_assign_categories(item_category_mapping)
        logger.info "=== Bulk assigning #{item_category_mapping.size} items to categories ==="

        success_count = 0
        error_count = 0
        errors = []

        # Process in smaller batches
        batch_size = 5
        item_category_mapping.keys.each_slice(batch_size) do |batch_item_ids|
          logger.info "Processing batch of #{batch_item_ids.size} items"

          batch_item_ids.each do |item_id|
            category_id = item_category_mapping[item_id]

            # Directly use category_items endpoint for each item
            payload = {
              "elements" => [
                {
                  "category" => { "id" => category_id },
                  "item" => { "id" => item_id }
                }
              ]
            }

            logger.info "Assigning item #{item_id} to category #{category_id}"

            begin
              response = make_request(:post, endpoint("category_items"), payload)

              if response && (response["elements"] || response.is_a?(Array))
                logger.info "✅ Successfully assigned item #{item_id} to category #{category_id}"
                success_count += 1
              else
                logger.error "❌ Failed to assign item #{item_id} to category #{category_id}"
                error_count += 1
                errors << "Failed to assign item #{item_id} to category #{category_id}"
              end
            rescue StandardError => e
              logger.error "Error assigning item #{item_id} to category #{category_id}: #{e.message}"
              error_count += 1
              errors << "Error: #{e.message} for item #{item_id}"
            end
          end
        end

        logger.info "=== Bulk assignment completed: #{success_count} successful, #{error_count} failed ==="

        {
          success: success_count > 0,
          updated_count: success_count,
          assigned_count: success_count,
          error_count: error_count,
          errors: errors
        }
      end

      # Add this method to your InventoryService class in lib/clover_restaurant/services/inventory_service.rb

      def direct_assign_item_to_category(item_id, category_id)
        logger.info "=== Directly assigning item #{item_id} to category #{category_id} ==="

        # Create the payload for a single assignment
        payload = {
          "elements" => [
            {
              "category" => { "id" => category_id },
              "item" => { "id" => item_id }
            }
          ]
        }

        # Log the payload for debugging
        logger.info "Request payload: #{payload.inspect}"

        # Make the API request to the category_items endpoint
        response = make_request(:post, endpoint("category_items"), payload)

        # Log the response for debugging
        logger.info "Response: #{response.inspect}"

        # Check response
        if response && (response["elements"] || response.is_a?(Array))
          logger.info "✅ Successfully assigned item #{item_id} to category #{category_id}"
          true
        else
          logger.error "❌ Failed to assign item #{item_id} to category #{category_id}"
          false
        end
      end

      # This is the fixed bulk assignment method
      def bulk_assign_items_to_categories_v2(item_category_mapping)
        logger.info "=== Performing bulk assignment of #{item_category_mapping.size} items to categories (v2) ==="

        success_count = 0
        failed_count = 0
        errors = []

        # Process each item individually for reliability
        item_category_mapping.each do |item_id, category_id|
          logger.info "Processing item #{item_id} for category #{category_id}"

          begin
            if direct_assign_item_to_category(item_id, category_id)
              success_count += 1
            else
              failed_count += 1
              errors << "Failed to assign item #{item_id} to category #{category_id}"
            end
          rescue StandardError => e
            logger.error "Error processing item #{item_id}: #{e.message}"
            failed_count += 1
            errors << "Error: #{e.message}"
          end

          # Small pause to avoid overwhelming the API
          sleep(0.2)
        end

        logger.info "=== Bulk assignment completed: #{success_count} successful, #{failed_count} failed ==="

        {
          success: success_count > 0,
          updated_count: success_count,
          failed_count: failed_count,
          errors: errors
        }
      end

      # This is a completely rewritten version of auto_assign_items_to_categories
      def auto_assign_items_to_categories_v2(items = nil, categories = nil)
        logger.info "=== Auto-assigning items to categories (v2) ==="

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

        if items.nil? || items.empty? || categories.nil? || categories.empty?
          return { success: false,
                   errors: ["No items or categories available"] }
        end

        logger.info "Working with #{items.size} items and #{categories.size} categories"

        # Define category keywords for matching
        category_keywords = {
          "appetizer" => %w[appetizer soup salad starter],
          "entree" => %w[burger sandwich pasta steak chicken fish entrée entree pizza],
          "side" => %w[side fries potato rice beans],
          "dessert" => ["dessert", "cake", "ice cream", "sweet", "chocolate"],
          "drink" => %w[drink beverage soda coffee tea juice],
          "alcoholic" => %w[beer wine cocktail spirit alcohol]
        }

        # Map categories to their IDs for lookup
        category_name_to_id = {}
        categories.each do |category|
          category_name_to_id[category["name"].downcase] = category["id"]
        end

        # Find a default category (using the first one as fallback)
        default_category = categories.find { |c| c["name"].downcase.include?("special") } || categories.first

        # Print found categories
        logger.info "Found categories:"
        categories.each do |category|
          logger.info "  - #{category["name"]} (ID: #{category["id"]})"
        end

        # Store item-to-category mappings
        item_category_mapping = {}
        uncategorized_items = []

        # Process each item
        items.each do |item|
          item_id = item["id"]
          item_name = item["name"]

          # Check if item already has categories
          has_categories = false

          if item["categories"] && item["categories"].is_a?(Hash) &&
             item["categories"]["elements"] && !item["categories"]["elements"].empty?
            logger.info "Item #{item_name} already has categories (Hash structure)"
            has_categories = true
          elsif item["categories"] && item["categories"].is_a?(Array) && !item["categories"].empty?
            logger.info "Item #{item_name} already has categories (Array structure)"
            has_categories = true
          end

          if has_categories
            logger.info "Skipping already categorized item: #{item_name}"
            next
          end

          # Try to match the item to a category
          item_name_lower = item_name.downcase
          assigned = false

          # Try each category based on keywords
          category_keywords.each do |key, keywords|
            next unless keywords.any? { |kw| item_name_lower.include?(kw) }

            # Find a matching category
            matching_category = categories.find do |cat|
              cat_name = cat["name"].downcase
              cat_name.include?(key) || keywords.any? { |kw| cat_name.include?(kw) }
            end

            next unless matching_category

            logger.info "Matched item '#{item_name}' to category '#{matching_category["name"]}'"
            item_category_mapping[item_id] = matching_category["id"]
            assigned = true
            break
          end

          # If no match found, use default category
          unless assigned
            if default_category
              logger.info "Using default category '#{default_category["name"]}' for item '#{item_name}'"
              item_category_mapping[item_id] = default_category["id"]
            else
              logger.warn "No suitable category found for item '#{item_name}'"
              uncategorized_items << item_name
            end
          end
        end

        # Report uncategorized items
        if uncategorized_items.any?
          logger.warn "#{uncategorized_items.size} items could not be categorized:"
          uncategorized_items.each { |name| logger.warn "  - #{name}" }
        end

        # If we have assignments to make, execute them
        if item_category_mapping.any?
          logger.info "Found #{item_category_mapping.size} items to assign to categories"

          # Log the assignments
          item_category_mapping.each do |item_id, category_id|
            item_name = begin
              items.find { |i| i["id"] == item_id }["name"]
            rescue StandardError
              "Unknown"
            end
            category_name = begin
              categories.find { |c| c["id"] == category_id }["name"]
            rescue StandardError
              "Unknown"
            end
            logger.info "Will assign: #{item_name} -> #{category_name}"
          end

          # Perform the assignments
          bulk_assign_items_to_categories_v2(item_category_mapping)
        else
          logger.info "No assignments to make"
          { success: true, updated_count: 0, message: "No items needed assignment" }
        end
      end

      # Enhanced bulk_assign_items_to_categories method with better error handling
      def bulk_assign_items_to_categories(item_category_mapping)
        logger.info "=== Performing bulk assignment of #{item_category_mapping.size} items to categories ==="

        success_count = 0
        error_count = 0
        errors = []

        # Process items in batches to avoid overwhelming the API
        batch_size = 20
        item_category_mapping.keys.each_slice(batch_size) do |batch_item_ids|
          batch_mapping = {}
          batch_item_ids.each { |id| batch_mapping[id] = item_category_mapping[id] }

          # Try the category_items endpoint first
          begin
            # Build the bulk payload
            elements = []
            batch_mapping.each do |item_id, category_id|
              elements << {
                "category" => { "id" => category_id },
                "item" => { "id" => item_id }
              }
            end

            payload = { "elements" => elements }

            # Make the bulk request
            response = make_request(:post, endpoint("category_items"), payload)

            if response && (response["elements"] || response.is_a?(Array))
              success_elements = response["elements"] || response
              logger.info "✅ Successfully assigned #{success_elements.size} items to categories in batch"
              success_count += success_elements.size
            else
              # Fallback to individual assignments
              logger.warn "Bulk assignment failed, falling back to individual assignments"
              batch_mapping.each do |item_id, category_id|
                if assign_category_to_item(item_id, category_id)
                  success_count += 1
                else
                  error_count += 1
                  errors << "Failed to assign item #{item_id} to category #{category_id}"
                end
              end
            end
          rescue StandardError => e
            logger.error "Error in batch assignment: #{e.message}"
            errors << "Batch error: #{e.message}"

            # Fallback to individual assignments
            logger.warn "Trying individual assignments for batch after error"
            batch_mapping.each do |item_id, category_id|
              if assign_category_to_item(item_id, category_id)
                success_count += 1
              else
                error_count += 1
                errors << "Failed to assign item #{item_id} to category #{category_id}"
              end
            rescue StandardError => individual_error
              error_count += 1
              errors << "Error assigning item #{item_id} to category #{category_id}: #{individual_error.message}"
            end
          end
        end

        logger.info "=== Bulk assignment completed: #{success_count} successful, #{error_count} failed ==="

        {
          success: success_count > 0,
          updated_count: success_count,
          assigned_count: success_count,
          error_count: error_count,
          errors: errors
        }
      end

      # Helper method to assign a single item to a category
      def assign_category_to_item(item_id, category_id)
        logger.info "=== Assigning item #{item_id} to category #{category_id} ==="

        # Check if item already has this category
        item = get_item(item_id)

        if item && item["categories"] && item["categories"]["elements"] &&
           item["categories"]["elements"].any? { |cat| cat["id"] == category_id }
          logger.info "Item #{item_id} already has category #{category_id}, skipping"
          return true
        end

        # Create the payload for a single assignment
        payload = {
          "elements" => [
            {
              "category" => { "id" => category_id },
              "item" => { "id" => item_id }
            }
          ]
        }

        # Make the API request
        response = make_request(:post, endpoint("categories"), payload)

        # Check response
        if response && (response["elements"] || response.is_a?(Array))
          logger.info "✅ Successfully assigned item #{item_id} to category #{category_id}"
          true
        else
          logger.error "❌ Failed to assign item #{item_id} to category #{category_id}"
          false
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

        # Use bulk assignment if we have items to assign
        if item_category_mapping.any?
          bulk_assign_categories(item_category_mapping)
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
