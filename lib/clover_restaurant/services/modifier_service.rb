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

      def get_modifier_group(group_id)
        logger.info "Fetching modifier group #{group_id} for merchant #{@config.merchant_id}"
        make_request(:get, endpoint("modifier_groups/#{group_id}"))
      end

      def create_modifier_group(group_data)
        logger.info "Creating new modifier group for merchant #{@config.merchant_id}"
        make_request(:post, endpoint("modifier_groups"), group_data)
      end

      def create_modifier(group_id, modifier_data)
        logger.info "Creating new modifier in group #{group_id} for merchant #{@config.merchant_id}"
        make_request(:post, endpoint("modifier_groups/#{group_id}/modifiers"), modifier_data)
      end

      def create_common_modifier_groups
        logger.info "Creating common modifier groups"

        # Define common modifier groups with their modifiers
        modifier_groups = {
          "Steak Temperature" => {
            name: "Steak Temperature",
            modifiers: [
              { name: "Rare", price: 0 },
              { name: "Medium Rare", price: 0 },
              { name: "Medium", price: 0 },
              { name: "Medium Well", price: 0 },
              { name: "Well Done", price: 0 }
            ],
            min_required: 1,
            max_allowed: 1,
            show_by_default: true
          },
          "Salad Dressing" => {
            name: "Salad Dressing",
            modifiers: [
              { name: "Ranch", price: 0 },
              { name: "Blue Cheese", price: 0 },
              { name: "Balsamic Vinaigrette", price: 0 },
              { name: "Caesar", price: 0 },
              { name: "Honey Mustard", price: 0 },
              { name: "Oil & Vinegar", price: 0 }
            ],
            min_required: 1,
            max_allowed: 1,
            show_by_default: true
          },
          "Protein Add-ons" => {
            name: "Protein Add-ons",
            modifiers: [
              { name: "Grilled Chicken", price: 495 },
              { name: "Grilled Shrimp", price: 695 },
              { name: "Salmon", price: 795 },
              { name: "Steak", price: 895 }
            ],
            min_required: 0,
            max_allowed: 2,
            show_by_default: false
          },
          "Sides Choice" => {
            name: "Sides Choice",
            modifiers: [
              { name: "French Fries", price: 0 },
              { name: "Sweet Potato Fries", price: 150 },
              { name: "Mashed Potatoes", price: 0 },
              { name: "Side Salad", price: 0 },
              { name: "Seasonal Vegetables", price: 0 },
              { name: "Onion Rings", price: 150 }
            ],
            min_required: 1,
            max_allowed: 1,
            show_by_default: true
          },
          "Drink Modifications" => {
            name: "Drink Modifications",
            modifiers: [
              { name: "Extra Shot", price: 100 },
              { name: "Sugar Free Syrup", price: 75 },
              { name: "Almond Milk", price: 75 },
              { name: "Oat Milk", price: 75 },
              { name: "Whipped Cream", price: 50 }
            ],
            min_required: 0,
            max_allowed: 5,
            show_by_default: false
          },
          "Pizza Toppings" => {
            name: "Pizza Toppings",
            modifiers: [
              { name: "Pepperoni", price: 200 },
              { name: "Mushrooms", price: 150 },
              { name: "Onions", price: 150 },
              { name: "Green Peppers", price: 150 },
              { name: "Extra Cheese", price: 200 },
              { name: "Italian Sausage", price: 200 },
              { name: "Black Olives", price: 150 }
            ],
            min_required: 0,
            max_allowed: 7,
            show_by_default: false
          },
          "Special Instructions" => {
            name: "Special Instructions",
            modifiers: [
              { name: "No Onions", price: 0 },
              { name: "No Garlic", price: 0 },
              { name: "Extra Spicy", price: 0 },
              { name: "Gluten Free (when possible)", price: 200 },
              { name: "Sauce on Side", price: 0 }
            ],
            min_required: 0,
            max_allowed: 5,
            show_by_default: false
          }
        }

        created_groups = []

        modifier_groups.each do |group_name, group_data|
          # Create the modifier group
          group = create_modifier_group({
            "name" => group_data[:name],
            "minRequired" => group_data[:min_required],
            "maxAllowed" => group_data[:max_allowed],
            "showByDefault" => group_data[:show_by_default]
          })

          if group && group["id"]
            logger.info "✅ Created modifier group: #{group["name"]}"

            # Create modifiers within the group
            group_data[:modifiers].each do |modifier|
              created_modifier = create_modifier(group["id"], {
                "name" => modifier[:name],
                "price" => modifier[:price]
              })

              if created_modifier && created_modifier["id"]
                logger.info "  ✓ Created modifier: #{created_modifier["name"]}"
              else
                logger.error "  ✗ Failed to create modifier: #{modifier[:name]}"
              end
            end

            created_groups << group
          else
            logger.error "❌ Failed to create modifier group: #{group_data[:name]}"
          end
        end

        created_groups
      end

      def assign_appropriate_modifiers_to_items(items)
        logger.info "Assigning appropriate modifiers to items"

        # Get all modifier groups
        modifier_groups = get_modifier_groups
        return unless modifier_groups && modifier_groups["elements"]

        # Create a map of modifier group names to IDs
        modifier_group_map = {}
        modifier_groups["elements"].each do |group|
          modifier_group_map[group["name"]] = group["id"]
        end

        # Define rules for assigning modifiers to items based on their names or categories
        assignment_rules = {
          "steak" => ["Steak Temperature", "Sides Choice"],
          "salad" => ["Salad Dressing", "Protein Add-ons"],
          "pizza" => ["Pizza Toppings"],
          "coffee" => ["Drink Modifications"],
          "burger" => ["Sides Choice"],
          "sandwich" => ["Sides Choice"],
          "pasta" => ["Protein Add-ons"]
        }

        # Assign modifiers to each item based on rules
        items.each do |item|
          item_name = item["name"].downcase
          item_categories = item["categories"]&.map { |c| c["name"]&.downcase } || []

          # Determine which modifier groups should be assigned
          groups_to_assign = []

          # Always add Special Instructions
          groups_to_assign << "Special Instructions"

          # Check name-based rules
          assignment_rules.each do |keyword, groups|
            if item_name.include?(keyword)
              groups_to_assign.concat(groups)
            end
          end

          # Check category-based rules
          if item_categories.include?("entrees")
            groups_to_assign << "Sides Choice"
          end

          # Make the assignments
          groups_to_assign.uniq.each do |group_name|
            group_id = modifier_group_map[group_name]
            next unless group_id

            begin
              make_request(:post, endpoint("modifier_groups/#{group_id}/items/#{item["id"]}"), {})
              logger.info "  ✓ Assigned '#{group_name}' to '#{item["name"]}'"
            rescue StandardError => e
              logger.error "  ✗ Failed to assign '#{group_name}' to '#{item["name"]}': #{e.message}"
            end
          end
        end
      end
    end
  end
end
