# lib/clover_restaurant/services/modifier_service.rb
module CloverRestaurant
  module Services
    class ModifierService < BaseService
      def get_modifier_groups(limit = 100, offset = 0)
        logger.info "=== Fetching modifier groups for merchant #{@config.merchant_id} ==="
        make_request(:get, endpoint("modifier_groups"), nil, { limit: limit, offset: offset })
      end

      def get_modifier_group(modifier_group_id)
        logger.info "=== Fetching modifier group #{modifier_group_id} for merchant #{@config.merchant_id} ==="
        make_request(:get, endpoint("modifier_groups/#{modifier_group_id}"))
      end

      def create_modifier_group(modifier_group_data)
        logger.info "=== Creating new modifier group for merchant #{@config.merchant_id} ==="

        # Check if a modifier group with the same name already exists
        existing_groups = get_modifier_groups
        if existing_groups && existing_groups["elements"]
          existing_group = existing_groups["elements"].find { |group| group["name"] == modifier_group_data["name"] }
          if existing_group
            logger.info "Modifier group '#{modifier_group_data["name"]}' already exists with ID: #{existing_group["id"]}, skipping creation"
            return existing_group
          end
        end

        logger.info "Modifier group data: #{modifier_group_data.inspect}"
        make_request(:post, endpoint("modifier_groups"), modifier_group_data)
      end

      def update_modifier_group(modifier_group_id, modifier_group_data)
        logger.info "=== Updating modifier group #{modifier_group_id} for merchant #{@config.merchant_id} ==="
        logger.info "Update data: #{modifier_group_data.inspect}"
        make_request(:post, endpoint("modifier_groups/#{modifier_group_id}"), modifier_group_data)
      end

      def delete_modifier_group(modifier_group_id)
        logger.info "=== Deleting modifier group #{modifier_group_id} for merchant #{@config.merchant_id} ==="
        make_request(:delete, endpoint("modifier_groups/#{modifier_group_id}"))
      end

      def get_modifiers(modifier_group_id, limit = 100, offset = 0)
        logger.info "=== Fetching modifiers for modifier group #{modifier_group_id} ==="
        make_request(:get, endpoint("modifier_groups/#{modifier_group_id}/modifiers"), nil,
                     { limit: limit, offset: offset })
      end

      def get_modifier(modifier_id)
        logger.info "=== Fetching modifier #{modifier_id} for merchant #{@config.merchant_id} ==="
        make_request(:get, endpoint("modifiers/#{modifier_id}"))
      end

      def create_modifier(modifier_data)
        logger.info "=== Creating new modifier for merchant #{@config.merchant_id} ==="

        # Check if this modifier already exists in the modifier group
        if modifier_data["modifierGroup"] && modifier_data["modifierGroup"]["id"]
          group_modifiers = get_modifiers(modifier_data["modifierGroup"]["id"])
          if group_modifiers && group_modifiers["elements"]
            existing_modifier = group_modifiers["elements"].find { |mod| mod["name"] == modifier_data["name"] }
            if existing_modifier
              logger.info "Modifier '#{modifier_data["name"]}' already exists in group with ID: #{existing_modifier["id"]}, skipping creation"
              return existing_modifier
            end
          end
        end

        logger.info "Modifier data: #{modifier_data.inspect}"
        make_request(:post, endpoint("modifiers"), modifier_data)
      end

      def update_modifier(modifier_id, modifier_data)
        logger.info "=== Updating modifier #{modifier_id} for merchant #{@config.merchant_id} ==="
        logger.info "Update data: #{modifier_data.inspect}"
        make_request(:post, endpoint("modifiers/#{modifier_id}"), modifier_data)
      end

      def delete_modifier(modifier_id)
        logger.info "=== Deleting modifier #{modifier_id} for merchant #{@config.merchant_id} ==="
        make_request(:delete, endpoint("modifiers/#{modifier_id}"))
      end

      def add_modifier_group_to_item(item_id, modifier_group_id)
        logger.info "=== Adding modifier group #{modifier_group_id} to item #{item_id} ==="

        # Check if this modifier group is already added to the item
        item_modifier_groups = get_item_modifier_groups(item_id)
        if item_modifier_groups && item_modifier_groups["elements"] && item_modifier_groups["elements"].any? do |group|
          group["id"] == modifier_group_id
        end
          logger.info "Modifier group #{modifier_group_id} already added to item #{item_id}, skipping"
          return true
        end

        payload = {
          "modifierGroup" => { "id" => modifier_group_id }
        }
        logger.info "Request payload: #{payload.inspect}"
        make_request(:post, endpoint("items/#{item_id}/modifier_groups"), payload)
      end

      def remove_modifier_group_from_item(item_id, modifier_group_id)
        logger.info "=== Removing modifier group #{modifier_group_id} from item #{item_id} ==="
        make_request(:delete, endpoint("items/#{item_id}/modifier_groups/#{modifier_group_id}"))
      end

      def get_item_modifier_groups(item_id)
        logger.info "=== Fetching modifier groups for item #{item_id} ==="
        make_request(:get, endpoint("items/#{item_id}/modifier_groups"))
      end

      def create_common_modifier_groups
        logger.info "=== Creating common restaurant modifier groups ==="

        # Check if common modifier groups already exist
        existing_groups = get_modifier_groups
        if existing_groups && existing_groups["elements"] && !existing_groups["elements"].empty?
          common_group_names = ["Size Options", "Temperature", "Add-ons", "Dressing Options",
                                "Protein Options", "Spice Level", "Bread Options"]

          existing_common_groups = existing_groups["elements"].select do |group|
            common_group_names.include?(group["name"])
          end

          if existing_common_groups.size >= 5
            logger.info "Found #{existing_common_groups.size} common modifier groups, skipping creation"
            return existing_common_groups
          end
        end

        # Define common modifier groups for restaurant items
        groups_config = [
          {
            name: "Size Options",
            selection_type: "SINGLE",
            modifiers: [
              { name: "Small", price: 0 },
              { name: "Medium", price: 200 },
              { name: "Large", price: 400 }
            ]
          },
          {
            name: "Temperature",
            selection_type: "SINGLE",
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
            selection_type: "MULTIPLE",
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
            selection_type: "SINGLE",
            modifiers: [
              { name: "Ranch", price: 0 },
              { name: "Italian", price: 0 },
              { name: "Balsamic Vinaigrette", price: 0 },
              { name: "Thousand Island", price: 0 },
              { name: "Blue Cheese", price: 0 }
            ]
          },
          {
            name: "Protein Options",
            selection_type: "SINGLE",
            modifiers: [
              { name: "Chicken", price: 300 },
              { name: "Beef", price: 400 },
              { name: "Shrimp", price: 500 },
              { name: "Tofu", price: 200 },
              { name: "No Protein", price: 0 }
            ]
          },
          {
            name: "Spice Level",
            selection_type: "SINGLE",
            modifiers: [
              { name: "Mild", price: 0 },
              { name: "Medium", price: 0 },
              { name: "Hot", price: 0 },
              { name: "Extra Hot", price: 0 }
            ]
          },
          {
            name: "Bread Options",
            selection_type: "SINGLE",
            modifiers: [
              { name: "White", price: 0 },
              { name: "Wheat", price: 0 },
              { name: "Sourdough", price: 50 },
              { name: "Gluten-Free", price: 150 }
            ]
          }
        ]

        created_groups = []
        success_count = 0
        error_count = 0

        groups_config.each_with_index do |group_config, index|
          logger.info "Creating group #{index + 1}/#{groups_config.size}: #{group_config[:name]}"

          group_data = {
            "name" => group_config[:name],
            "selectionType" => group_config[:selection_type]
          }

          begin
            group = create_modifier_group(group_data)

            if group && group["id"]
              created_groups << group
              success_count += 1
              logger.info "Successfully created modifier group: #{group["name"]} with ID: #{group["id"]}"

              # Create modifiers for this group
              group_config[:modifiers].each_with_index do |modifier_config, mod_index|
                logger.info "Creating modifier #{mod_index + 1}/#{group_config[:modifiers].size}: #{modifier_config[:name]}"

                modifier_data = {
                  "name" => modifier_config[:name],
                  "price" => modifier_config[:price],
                  "modifierGroup" => { "id" => group["id"] },
                  "sortOrder" => mod_index * 10
                }

                begin
                  modifier = create_modifier(modifier_data)
                  if modifier && modifier["id"]
                    logger.info "Successfully created modifier: #{modifier["name"]} with ID: #{modifier["id"]}"
                  else
                    logger.warn "Failed to create modifier or received unexpected response: #{modifier.inspect}"
                    error_count += 1
                  end
                rescue StandardError => e
                  logger.error "Error creating modifier: #{e.message}"
                  error_count += 1
                end
              end
            else
              logger.warn "Failed to create modifier group or received unexpected response: #{group.inspect}"
              error_count += 1
            end
          rescue StandardError => e
            logger.error "Error creating modifier group: #{e.message}"
            error_count += 1
          end
        end

        logger.info "=== Finished creating modifier groups: #{success_count} groups successful, #{error_count} errors ==="
        created_groups
      end

      def assign_appropriate_modifiers_to_items(items)
        logger.info "=== Assigning appropriate modifiers to items ==="

        # Get all modifier groups
        all_groups = get_modifier_groups
        unless all_groups && all_groups["elements"]
          logger.error "No modifier groups found"
          return false
        end

        group_map = {}
        all_groups["elements"].each do |group|
          group_map[group["name"]] = group
        end

        # Create common groups if they don't exist
        if group_map.empty? || group_map.keys.length < 5
          logger.info "Insufficient modifier groups found, creating common ones"
          created_groups = create_common_modifier_groups
          created_groups.each do |group|
            group_map[group["name"]] = group
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
        skipped_count = 0
        error_count = 0

        items.each_with_index do |item, index|
          logger.info "Processing item #{index + 1}/#{items.size}: #{item["name"]}"

          # Skip items that already have modifier groups assigned
          item_modifier_groups = get_item_modifier_groups(item["id"])
          if item_modifier_groups && item_modifier_groups["elements"] && !item_modifier_groups["elements"].empty?
            logger.info "Item #{item["name"]} already has #{item_modifier_groups["elements"].size} modifier groups, skipping"
            skipped_count += 1
            next
          end

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
          # Use a consistent seed based on item ID to ensure the same result for VCR
          random_seed = item["id"].to_s.chars.map(&:ord).sum % 100
          applicable_modifiers << "Spice Level" if random_seed < 30 && !applicable_modifiers.include?("Spice Level")

          logger.info "Assigning #{applicable_modifiers.size} modifiers to item #{item["name"]}"

          # Assign modifier groups to item
          applicable_modifiers.each do |modifier_name|
            if group_map[modifier_name]
              begin
                logger.info "Adding #{modifier_name} to item #{item["name"]}"
                add_modifier_group_to_item(item["id"], group_map[modifier_name]["id"])
                assigned_count += 1
              rescue StandardError => e
                logger.error "Error assigning modifier #{modifier_name} to item #{item["name"]}: #{e.message}"
                error_count += 1
              end
            else
              logger.warn "Modifier group '#{modifier_name}' not found in available groups"
            end
          end
        end

        logger.info "=== Finished assigning modifiers: #{assigned_count} assignments, #{skipped_count} skipped, #{error_count} errors ==="
        true
      end
    end
  end
end
