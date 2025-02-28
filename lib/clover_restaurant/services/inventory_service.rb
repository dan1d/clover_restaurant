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
    end
  end
end
