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
        logger.info "Modifier group data: #{modifier_group_data.inspect}"
        result = make_request(:post, endpoint("modifier_groups"), modifier_group_data)
        logger.info "Created modifier group: #{result.inspect}"
        result
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
        endpoint_path = endpoint("modifier_groups/#{modifier_group_id}/modifiers")
        logger.info "Using endpoint: #{endpoint_path}"
        make_request(:get, endpoint_path, nil, { limit: limit, offset: offset })
      end

      def get_modifier(modifier_id)
        logger.info "=== Fetching modifier #{modifier_id} for merchant #{@config.merchant_id} ==="
        make_request(:get, endpoint("modifiers/#{modifier_id}"))
      end

      def create_modifier(modifier_data)
        logger.info "=== Creating new modifier for merchant #{@config.merchant_id} ==="
        logger.info "Modifier data: #{modifier_data.inspect}"

        # Debug the modifier group relationship
        if modifier_data["modifierGroup"] && modifier_data["modifierGroup"]["id"]
          logger.info "Modifier has valid group ID: #{modifier_data["modifierGroup"]["id"]}"
        else
          logger.warn "WARNING: Modifier missing required modifierGroup.id field"
        end

        # Try multiple approaches if the default one fails
        begin
          endpoint_path = endpoint("modifiers")
          logger.info "Attempting to create modifier using endpoint: #{endpoint_path}"
          result = make_request(:post, endpoint_path, modifier_data)
          logger.info "Successfully created modifier: #{result.inspect}"
          result
        rescue StandardError => e
          logger.error "Failed to create modifier using default endpoint: #{e.message}"

          # Try alternate endpoint if we have a modifier group ID
          raise e unless modifier_data["modifierGroup"] && modifier_data["modifierGroup"]["id"]

          group_id = modifier_data["modifierGroup"]["id"]
          begin
            alternate_endpoint = endpoint("modifier_groups/#{group_id}/modifiers")
            logger.info "Trying alternate endpoint: #{alternate_endpoint}"
            result = make_request(:post, alternate_endpoint, modifier_data)
            logger.info "Successfully created modifier using alternate endpoint"
            result
          rescue StandardError => e2
            logger.error "Failed using alternate endpoint too: #{e2.message}"
            raise e2 # Re-raise the error if both attempts fail
          end

          # Re-raise the original error
        end
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
        payload = {
          "modifierGroup" => { "id" => modifier_group_id }
        }
        logger.info "Request payload: #{payload.inspect}"
        endpoint_path = endpoint("items/#{item_id}/modifier_groups")
        logger.info "Using endpoint: #{endpoint_path}"
        make_request(:post, endpoint_path, payload)
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

        groups_config.each_with_index do |group_config, group_index|
          logger.info "=== Creating modifier group #{group_index + 1}/#{groups_config.size}: #{group_config[:name]} ==="

          group_data = {
            "name" => group_config[:name],
            "selectionType" => group_config[:selection_type]
          }

          logger.info "Group data: #{group_data.inspect}"

          begin
            group = create_modifier_group(group_data)

            if group && group["id"]
              logger.info "Successfully created modifier group: #{group["name"]} with ID: #{group["id"]}"
              created_groups << group

              # Create modifiers for this group
              logger.info "=== Creating modifiers for group: #{group["name"]} ==="

              success_count = 0
              error_count = 0

              group_config[:modifiers].each_with_index do |modifier_config, index|
                modifier_data = {
                  "name" => modifier_config[:name],
                  "price" => modifier_config[:price],
                  "modifierGroup" => { "id" => group["id"] },
                  "sortOrder" => index * 10
                }

                logger.info "Creating modifier #{index + 1}/#{group_config[:modifiers].size}: #{modifier_config[:name]}"

                begin
                  result = create_modifier(modifier_data)
                  if result && result["id"]
                    logger.info "Successfully created modifier: #{modifier_config[:name]} with ID: #{result["id"]}"
                    success_count += 1
                  else
                    logger.warn "Created modifier but received unexpected response: #{result.inspect}"
                    error_count += 1
                  end
                rescue StandardError => e
                  logger.error "Failed to create modifier: #{e.message}"
                  logger.error "Modifier data was: #{modifier_data.inspect}"
                  error_count += 1
                  # Continue with next modifier even after error
                end
              end

              logger.info "=== Finished creating modifiers for group #{group["name"]}: #{success_count} successful, #{error_count} failed ==="
            else
              logger.error "Failed to create modifier group - received invalid response: #{group.inspect}"
            end
          rescue StandardError => e
            logger.error "Failed to create modifier group: #{e.message}"
            logger.error "Group data was: #{group_data.inspect}"
          end
        end

        logger.info "=== Finished creating modifier groups. Total created: #{created_groups.size} ==="
        created_groups
      end

      def assign_appropriate_modifiers_to_items(items)
        logger.info "=== Assigning appropriate modifiers to items ==="

        # Get all modifier groups
        logger.info "Fetching existing modifier groups"
        all_groups = get_modifier_groups

        unless all_groups && all_groups["elements"]
          logger.error "Failed to retrieve modifier groups or received empty response"
          return false
        end

        logger.info "Found #{all_groups["elements"].size} existing modifier groups"

        group_map = {}
        all_groups["elements"].each do |group|
          group_map[group["name"]] = group
          logger.info "  - Group: #{group["name"]} (ID: #{group["id"]})"
        end

        # Create common groups if they don't exist
        if group_map.empty? || group_map.keys.length < 5
          logger.info "Insufficient modifier groups found, creating common groups"
          created_groups = create_common_modifier_groups
          created_groups.each do |group|
            group_map[group["name"]] = group
            logger.info "Added new group to map: #{group["name"]} (ID: #{group["id"]})"
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
        error_count = 0

        items.each_with_index do |item, index|
          logger.info "=== Processing item #{index + 1}/#{items.size}: #{item["name"]} ==="
          item_name = item["name"].downcase

          # Find appropriate modifier groups
          applicable_modifiers = []

          # Check for specific matches
          item_to_modifier_mapping.each do |key, modifiers|
            next unless item_name.include?(key)

            applicable_modifiers = modifiers
            logger.info "Found matching key '#{key}' for item '#{item_name}'"
            break
          end

          # Use default if no specific match
          if applicable_modifiers.empty?
            logger.info "No specific match found for '#{item_name}', using default modifiers"
            applicable_modifiers = default_modifiers
          end

          # Add random modifiers (for variety)
          if rand < 0.3 && !applicable_modifiers.include?("Spice Level")
            logger.info "Randomly adding 'Spice Level' modifier"
            applicable_modifiers << "Spice Level"
          end

          logger.info "Applicable modifiers for '#{item_name}': #{applicable_modifiers.inspect}"

          # Assign modifier groups to item
          applicable_modifiers.each do |modifier_name|
            unless group_map[modifier_name]
              logger.warn "Modifier group '#{modifier_name}' not found in available groups"
              next
            end

            logger.info "Assigning modifier group '#{modifier_name}' (ID: #{group_map[modifier_name]["id"]}) to item '#{item["name"]}' (ID: #{item["id"]})"

            begin
              add_modifier_group_to_item(item["id"], group_map[modifier_name]["id"])
              assigned_count += 1
              logger.info "Successfully assigned modifier group"
            rescue StandardError => e
              logger.error "Error assigning modifier #{modifier_name} to item #{item["name"]}: #{e.message}"
              error_count += 1
            end
          end
        end

        logger.info "=== Finished assigning modifiers: #{assigned_count} successful, #{error_count} failed ==="
        true
      end
    end
  end
end
