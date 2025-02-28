# lib/clover_restaurant/services/menu_service.rb
module CloverRestaurant
  module Services
    class MenuService < BaseService
      def get_menus(limit = 100, offset = 0)
        logger.info "=== Fetching menus for merchant #{@config.merchant_id} ==="
        make_request(:get, endpoint("menus"), nil, { limit: limit, offset: offset })
      end

      def get_menu(menu_id)
        logger.info "=== Fetching menu #{menu_id} for merchant #{@config.merchant_id} ==="
        make_request(:get, endpoint("menus/#{menu_id}"))
      end

      def create_menu(menu_data)
        logger.info "=== Creating new menu for merchant #{@config.merchant_id} ==="

        # Check if menu with the same name already exists
        existing_menus = get_menus
        if existing_menus && existing_menus["elements"]
          existing_menu = existing_menus["elements"].find { |m| m["name"] == menu_data["name"] }
          if existing_menu
            logger.info "Menu '#{menu_data["name"]}' already exists with ID: #{existing_menu["id"]}, skipping creation"
            return existing_menu
          end
        end

        logger.info "Menu data: #{menu_data.inspect}"
        make_request(:post, endpoint("menus"), menu_data)
      end

      def update_menu(menu_id, menu_data)
        logger.info "=== Updating menu #{menu_id} for merchant #{@config.merchant_id} ==="
        logger.info "Update data: #{menu_data.inspect}"
        make_request(:post, endpoint("menus/#{menu_id}"), menu_data)
      end

      def delete_menu(menu_id)
        logger.info "=== Deleting menu #{menu_id} for merchant #{@config.merchant_id} ==="
        make_request(:delete, endpoint("menus/#{menu_id}"))
      end

      def get_menu_categories(menu_id, limit = 100, offset = 0)
        logger.info "=== Fetching categories for menu #{menu_id} ==="
        make_request(:get, endpoint("menus/#{menu_id}/categories"), nil, { limit: limit, offset: offset })
      end

      def add_category_to_menu(menu_id, category_id, sort_order = nil)
        logger.info "=== Adding category #{category_id} to menu #{menu_id} ==="

        # Check if category is already on this menu
        menu_categories = get_menu_categories(menu_id)
        if menu_categories && menu_categories["elements"] && menu_categories["elements"].any? do |mc|
          mc["category"] && mc["category"]["id"] == category_id
        end
          logger.info "Category #{category_id} already exists on menu #{menu_id}, skipping"
          return menu_categories["elements"].find { |mc| mc["category"]["id"] == category_id }
        end

        menu_category_data = {
          "menu" => { "id" => menu_id },
          "category" => { "id" => category_id }
        }

        menu_category_data["sortOrder"] = sort_order if sort_order

        logger.info "Request payload: #{menu_category_data.inspect}"
        make_request(:post, endpoint("menu_categories"), menu_category_data)
      end

      def remove_category_from_menu(menu_id, category_id)
        logger.info "=== Removing category #{category_id} from menu #{menu_id} ==="

        # First get the menu_category id
        menu_categories = get_menu_categories(menu_id)

        return false unless menu_categories && menu_categories["elements"]

        menu_category = menu_categories["elements"].find do |mc|
          mc["category"] && mc["category"]["id"] == category_id
        end

        return false unless menu_category && menu_category["id"]

        make_request(:delete, endpoint("menu_categories/#{menu_category["id"]}"))
      end

      def get_menu_items(menu_id, category_id = nil, limit = 100, offset = 0)
        logger.info "=== Fetching menu items for menu #{menu_id} ==="

        query_params = { limit: limit, offset: offset }

        query_params[:filter] = "category.id=#{category_id}" if category_id

        make_request(:get, endpoint("menus/#{menu_id}/items"), nil, query_params)
      end

      def create_menu_item(menu_id, category_id, item_id, sort_order = nil)
        logger.info "=== Creating menu item for item #{item_id} in category #{category_id} on menu #{menu_id} ==="

        # Check if item is already on this menu in this category
        menu_items = get_menu_items(menu_id, category_id)
        if menu_items && menu_items["elements"] && menu_items["elements"].any? do |mi|
          mi["item"] && mi["item"]["id"] == item_id
        end
          logger.info "Item #{item_id} already exists in category #{category_id} on menu #{menu_id}, skipping"
          return menu_items["elements"].find { |mi| mi["item"]["id"] == item_id }
        end

        # First add category to menu if not already there
        menu_categories = get_menu_categories(menu_id)

        unless menu_categories && menu_categories["elements"] &&
               menu_categories["elements"].find { |mc| mc["category"] && mc["category"]["id"] == category_id }
          add_category_to_menu(menu_id, category_id)
        end

        # Then add the item to the menu category
        menu_item_data = {
          "menu" => { "id" => menu_id },
          "category" => { "id" => category_id },
          "item" => { "id" => item_id }
        }

        menu_item_data["sortOrder"] = sort_order if sort_order

        logger.info "Request payload: #{menu_item_data.inspect}"
        make_request(:post, endpoint("menu_items"), menu_item_data)
      end

      def create_standard_menu(menu_name = "Standard Menu", categories = nil, items = nil)
        logger.info "=== Creating standard menu: #{menu_name} ==="

        # Check if menu already exists
        existing_menus = get_menus
        if existing_menus && existing_menus["elements"]
          existing_menu = existing_menus["elements"].find { |m| m["name"] == menu_name }
          if existing_menu
            logger.info "Menu '#{menu_name}' already exists with ID: #{existing_menu["id"]}, checking items"

            # Check if menu already has items
            menu_items = get_menu_items(existing_menu["id"])
            if menu_items && menu_items["elements"] && menu_items["elements"].size >= 10
              logger.info "Menu already has #{menu_items["elements"].size} items, skipping creation"
              return existing_menu
            end
          end
        end

        # Get inventory service to fetch categories and items if not provided
        inventory_service = InventoryService.new(@config)

        if categories.nil?
          categories_response = inventory_service.get_categories
          categories = categories_response && categories_response["elements"] ? categories_response["elements"] : []
        end

        if items.nil?
          items_response = inventory_service.get_items
          items = items_response && items_response["elements"] ? items_response["elements"] : []
        end

        return nil if categories.empty? || items.empty?

        # Create the menu
        menu = create_menu({
                             "name" => menu_name
                           })

        return nil unless menu && menu["id"]

        menu_id = menu["id"]

        # Map items by category
        items_by_category = {}

        items.each do |item|
          # Get categories for this item
          item_categories_response = make_request(:get, endpoint("items/#{item["id"]}/categories"))

          next unless item_categories_response && item_categories_response["elements"]

          item_categories_response["elements"].each do |ic|
            category_id = ic["category"]["id"]
            items_by_category[category_id] ||= []
            items_by_category[category_id] << item
          end
        end

        # Add categories and items to menu
        success_count = 0
        error_count = 0

        categories.each_with_index do |category, category_index|
          logger.info "Processing category #{category_index + 1}/#{categories.size}: #{category["name"]}"
          category_id = category["id"]

          # Add category to menu
          begin
            add_category_to_menu(menu_id, category_id, category_index * 100)

            # Add items for this category
            next unless items_by_category[category_id]

            items_by_category[category_id].each_with_index do |item, item_index|
              logger.info "Adding item #{item_index + 1}/#{items_by_category[category_id].size}: #{item["name"]}"
              begin
                create_menu_item(menu_id, category_id, item["id"], item_index * 10)
                success_count += 1
              rescue StandardError => e
                logger.error "Failed to add item to menu: #{e.message}"
                error_count += 1
              end
            end
          rescue StandardError => e
            logger.error "Failed to add category to menu: #{e.message}"
            error_count += 1
          end
        end

        logger.info "=== Finished creating menu: added #{success_count} items, #{error_count} errors ==="

        menu
      end

      def create_time_based_menus(items = nil)
        logger.info "=== Creating time-based menus ==="

        # Check if time-based menus already exist
        existing_menus = get_menus
        if existing_menus && existing_menus["elements"]
          time_menu_names = ["Breakfast Menu", "Lunch Menu", "Dinner Menu", "Late Night Menu"]
          existing_time_menus = existing_menus["elements"].select { |m| time_menu_names.include?(m["name"]) }

          if existing_time_menus.size >= 3
            logger.info "Found #{existing_time_menus.size} time-based menus already existing, skipping creation"
            return existing_time_menus
          end
        end

        # Get inventory service to fetch items if not provided
        inventory_service = InventoryService.new(@config)

        if items.nil?
          items_response = inventory_service.get_items
          items = items_response && items_response["elements"] ? items_response["elements"] : []
        end

        return [] if items.empty?

        # Get categories
        categories_response = inventory_service.get_categories
        categories = categories_response && categories_response["elements"] ? categories_response["elements"] : []

        return [] if categories.empty?

        # Define time-based menus
        time_menus = [
          { name: "Breakfast Menu", start_time: "06:00", end_time: "11:00" },
          { name: "Lunch Menu", start_time: "11:00", end_time: "16:00" },
          { name: "Dinner Menu", start_time: "16:00", end_time: "22:00" },
          { name: "Late Night Menu", start_time: "22:00", end_time: "06:00" }
        ]

        created_menus = []

        time_menus.each_with_index do |menu_config, menu_index|
          logger.info "Creating menu #{menu_index + 1}/#{time_menus.size}: #{menu_config[:name]}"

          # Check if this time-based menu already exists
          existing_menus = get_menus
          if existing_menus && existing_menus["elements"]
            existing_menu = existing_menus["elements"].find { |m| m["name"] == menu_config[:name] }
            if existing_menu
              logger.info "Menu '#{menu_config[:name]}' already exists with ID: #{existing_menu["id"]}, using existing"
              created_menus << existing_menu
              next
            end
          end

          menu_data = {
            "name" => menu_config[:name],
            "timeSchedule" => {
              "start" => menu_config[:start_time],
              "end" => menu_config[:end_time]
            }
          }

          menu = create_menu(menu_data)

          next unless menu && menu["id"]

          created_menus << menu
          logger.info "Successfully created menu: #{menu["name"]} with ID: #{menu["id"]}"

          # Add category-appropriate items using deterministic filtering based on name
          case menu_config[:name]
          when "Breakfast Menu"
            breakfast_terms = %w[breakfast egg pancake waffle coffee juice bacon toast]
            add_filtered_items_to_menu(menu, categories, items, breakfast_terms)

          when "Lunch Menu"
            lunch_terms = %w[lunch sandwich salad soup wrap burger]
            add_filtered_items_to_menu(menu, categories, items, lunch_terms)

          when "Dinner Menu"
            dinner_terms = %w[dinner entree steak fish chicken pasta]
            add_filtered_items_to_menu(menu, categories, items, dinner_terms)

          when "Late Night Menu"
            late_night_terms = %w[appetizer dessert drink cocktail snack]
            add_filtered_items_to_menu(menu, categories, items, late_night_terms)
          end
        end

        created_menus
      end

      def add_filtered_items_to_menu(menu, categories, items, filter_terms)
        # Find appropriate categories first
        filtered_categories = categories.select do |category|
          filter_terms.any? { |term| category["name"].downcase.include?(term) }
        end

        # If no specific categories found, use generic ones
        filtered_categories = categories.first(3) if filtered_categories.empty?

        # Add each category to the menu
        filtered_categories.each_with_index do |category, cat_index|
          add_category_to_menu(menu["id"], category["id"], cat_index * 100)

          # Find appropriate items for this category
          filtered_items = items.select do |item|
            # Check if item belongs to this category
            item_in_category = false

            begin
              item_categories = make_request(:get, endpoint("items/#{item["id"]}/categories"))
              if item_categories && item_categories["elements"]
                item_in_category = item_categories["elements"].any? do |ic|
                  ic["category"] && ic["category"]["id"] == category["id"]
                end
              end
            rescue StandardError => e
              logger.error "Error checking item categories: #{e.message}"
            end

            # If item is in this category and matches a filter term, add it
            item_in_category && filter_terms.any? { |term| item["name"].downcase.include?(term) }
          end

          # If no specific items found, use all items in this category
          if filtered_items.empty?
            filtered_items = items.select do |item|
              item_categories = make_request(:get, endpoint("items/#{item["id"]}/categories"))
              if item_categories && item_categories["elements"]
                item_categories["elements"].any? do |ic|
                  ic["category"] && ic["category"]["id"] == category["id"]
                end
              end
            rescue StandardError => e
              logger.error "Error checking item categories: #{e.message}"
              false
            end
          end

          # Add items to menu
          filtered_items.each_with_index do |item, item_index|
            create_menu_item(menu["id"], category["id"], item["id"], item_index * 10)
          end
        end
      end

      def print_menu(menu_id, format = "text")
        logger.info "=== Generating menu #{menu_id} in #{format} format ==="

        menu = get_menu(menu_id)

        return nil unless menu

        menu_categories = get_menu_categories(menu_id)

        return nil unless menu_categories && menu_categories["elements"]

        # Build menu output
        output = ""

        case format
        when "text"
          output << "#{menu["name"].upcase}\n"
          output << "=" * menu["name"].length + "\n\n"

          menu_categories["elements"].each do |menu_category|
            category_name = menu_category["category"]["name"]

            output << "#{category_name}\n"
            output << "-" * category_name.length + "\n\n"

            menu_items = get_menu_items(menu_id, menu_category["category"]["id"])

            if menu_items && menu_items["elements"]
              menu_items["elements"].each do |menu_item|
                item = menu_item["item"]
                price = item["price"] / 100.0

                output << "#{item["name"]} ... $#{format("%.2f", price)}\n"

                output << "    #{item["description"]}\n" if item["description"] && !item["description"].empty?

                output << "\n"
              end
            end

            output << "\n"
          end
        when "html"
          output << "<div class='menu'>\n"
          output << "  <h1>#{menu["name"]}</h1>\n"

          menu_categories["elements"].each do |menu_category|
            category_name = menu_category["category"]["name"]

            output << "  <div class='menu-category'>\n"
            output << "    <h2>#{category_name}</h2>\n"

            menu_items = get_menu_items(menu_id, menu_category["category"]["id"])

            if menu_items && menu_items["elements"]
              output << "    <ul>\n"

              menu_items["elements"].each do |menu_item|
                item = menu_item["item"]
                price = item["price"] / 100.0

                output << "      <li class='menu-item'>\n"
                output << "        <div class='item-name'>#{item["name"]}</div>\n"
                output << "        <div class='item-price'>$#{format("%.2f", price)}</div>\n"

                if item["description"] && !item["description"].empty?
                  output << "        <div class='item-description'>#{item["description"]}</div>\n"
                end

                output << "      </li>\n"
              end

              output << "    </ul>\n"
            end

            output << "  </div>\n"
          end

          output << "</div>\n"
        end

        output
      end
    end
  end
end
