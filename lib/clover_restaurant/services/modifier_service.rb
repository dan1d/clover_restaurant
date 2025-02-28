# lib/clover_restaurant/services/modifier_service.rb
module CloverRestaurant
  module Services
    class ModifierService < BaseService
      def get_modifier_groups(limit = 100, offset = 0)
        logger.info "=== Fetching modifier groups for merchant #{@config.merchant_id} ==="
        response = make_request(:get, endpoint("modifier_groups"), nil, { limit: limit, offset: offset })

        if response && response["elements"]
          logger.info "✅ Successfully fetched #{response["elements"].size} modifier groups."
        else
          logger.warn "⚠️ WARNING: No modifier groups found or API response is empty!"
        end

        response
      end

      def create_modifier_group(modifier_group_data)
        logger.info "=== Checking if modifier group '#{modifier_group_data["name"]}' already exists ==="

        existing_groups = get_modifier_groups
        if existing_groups && existing_groups["elements"]
          existing_group = existing_groups["elements"].find do |group|
            group["name"].casecmp?(modifier_group_data["name"])
          end
          if existing_group
            logger.info "Modifier group '#{modifier_group_data["name"]}' already exists with ID: #{existing_group["id"]}, skipping creation."
            return existing_group
          end
        end

        # Only create new modifier groups if there are fewer than 2 existing ones
        if existing_groups["elements"].size >= 2
          logger.info "There are already #{existing_groups["elements"].size} modifier groups, skipping creation."
          return nil
        end

        logger.info "Creating new modifier group: #{modifier_group_data.inspect}"
        response = make_request(:post, endpoint("modifier_groups"), modifier_group_data)

        if response && response["id"]
          logger.info "Successfully created modifier group '#{response["name"]}' with ID: #{response["id"]}"
        else
          logger.error "ERROR: Modifier group creation failed. Response: #{response.inspect}"
        end

        response
      end

      def add_modifier_group_to_item(item_id, modifier_group_id)
        logger.info "=== Adding modifier group #{modifier_group_id} to item #{item_id} ==="

        begin
          payload = { "modifierGroup" => { "id" => modifier_group_id } }
          logger.info "Request payload: #{payload.inspect}"
          make_request(:post, endpoint("items/#{item_id}/modifier_groups"), payload)
        rescue APIError => e
          logger.info "Attempted to add modifier group #{modifier_group_id} to item #{item_id}, response: #{e.message}"
          true # Continue execution even if error
        end
      end

      def create_common_modifier_groups
        logger.info "=== Ensuring at least 2 modifier groups exist ==="

        existing_groups = get_modifier_groups
        if existing_groups && existing_groups["elements"] && existing_groups["elements"].size >= 2
          logger.info "Found #{existing_groups["elements"].size} modifier groups, no need to create more."
          return existing_groups["elements"]
        end

        groups_config = [
          { name: "Size Options", selectionType: "SINGLE" },
          { name: "Add-ons", selectionType: "MULTIPLE" }
        ]

        created_groups = []
        groups_config.each do |group_config|
          logger.info "Checking if '#{group_config[:name]}' exists before creating..."
          created_group = create_modifier_group(group_config)
          created_groups << created_group if created_group
        end

        logger.info "=== Finished creating modifier groups: #{created_groups.size} created ==="
        created_groups
      end
    end
  end
end
