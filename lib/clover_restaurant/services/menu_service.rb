# lib/clover_restaurant/services/menu_service.rb
module CloverRestaurant
  module Services
    class MenuService < BaseService
      def get_menus(limit = 100, offset = 0)
        logger.info "Fetching menus for merchant #{@config.merchant_id}"
        make_request(:get, endpoint("menus"), nil, { limit: limit, offset: offset })
      end

      def get_menu(menu_id)
        logger.info "Fetching menu #{menu_id} for merchant #{@config.merchant_id}"
        make_request(:get, endpoint("menus/#{menu_id}"))
      end

      def create_menu(menu_data)
        logger.info "Creating new menu for merchant #{@config.merchant_id}"
        make_request(:post, endpoint("menus"), menu_data)
      end

      def update_menu(menu_id, menu_data)
        logger.info "Updating menu #{menu_id} for merchant #{@config.merchant_id}"
        make_request(:post, endpoint("menus/#{menu_id}"), menu_data)
      end

      def delete_menu(menu_id)
        logger.info "Deleting menu #{menu_id} for merchant #{@config.merchant_id}"
        make_request(:delete, endpoint("menus/#{menu_id}"))
      end

      def get_menu_categories(menu_id, limit = 100, offset = 0)
        logger.info "Fetching categories for menu #{menu_id}"
        make_request(:get, endpoint("menus/#{menu_id}/categories"), nil, { limit: limit, offset: offset })
      end

      def add_category_to_menu(menu_id, category_id, sort_order = nil)
        logger.info "Adding category #{category_id} to menu #{menu_id}"

        menu_category_data = {
          "menu" => { "id" => menu_id },
          "category" => { "id" => category_id }
        }

        menu_category_data["sortOrder"] = sort_order if sort_order

        make_request(:post, endpoint("menu_categories"), menu_category_data)
      end

      def remove_category_from_menu(menu_id, category_id)
        logger.info "Removing category #{category_id} from menu #{menu_id}"

        # First get the menu_category id
        menu_categories = get_menu_categories(menu_id)

        return false unless menu_categories && menu_categories["elements"]

        menu_category = menu_categories["elements"].find do |mc|
          mc["category"] && mc["category"]["id"] == category_id
        end

        return false unless menu_category && menu_category["id"]

        make_request(:delete, endpoint("menu_categories/#{menu_category["id"]}"))
      end

      def create_menu_item(menu_id, category_id, item_id, sort_order = nil)
        logger.info "Creating menu item for item #{item_id} in category #{category_id} on menu #{menu_id}"

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

        make_request(:post, endpoint("menu_items"), menu_item_data)
      end

      def get_menu_items(menu_id, category_id = nil, limit = 100, offset = 0)
        logger.info "Fetching menu items for menu #{menu_id}"

        query_params = { limit: limit, offset: offset }

        query_params[:filter] = "category.id=#{category_id}" if category_id

        make_request(:get, endpoint("menus/#{menu_id}/items"), nil, query_params)
      end

      def create_standard_menu(menu_name = "Standard Menu", categories = nil, items = nil)
        logger.info "Creating standard menu: #{menu_name}"

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
        categories.each_with_index do |category, category_index|
          category_id = category["id"]

          # Add category to menu
          add_category_to_menu(menu_id, category_id, category_index * 100)

          # Add items for this category
          next unless items_by_category[category_id]

          items_by_category[category_id].each_with_index do |item, item_index|
            create_menu_item(menu_id, category_id, item["id"], item_index * 10)
          end
        end

        menu
      end

      def create_time_based_menus(items = nil)
        logger.info "Creating time-based menus"

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

        time_menus.each do |menu_config|
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

          # Add categories and items to this menu
          # For breakfast, focus on breakfast-related items
          # For lunch, focus on sandwiches, salads, etc.
          # For dinner, include entrees, appetizers, etc.
          # For late night, focus on appetizers, desserts, drinks

          case menu_config[:name]
          when "Breakfast Menu"
            breakfast_categories = categories.select { |c| c["name"].downcase.include?("breakfast") }

            # If no breakfast-specific categories, add generic ones
            if breakfast_categories.empty?
              breakfast_categories = categories.select do |c|
                %w[appetizer side drink].any? do |word|
                  c["name"].downcase.include?(word)
                end
              end
            end

            breakfast_categories.each_with_index do |category, index|
              add_category_to_menu(menu["id"], category["id"], index * 100)

              # Add breakfast items
              breakfast_items = items.select do |item|
                item["name"].downcase.match(/breakfast|egg|pancake|waffle|coffee|juice|muffin|bacon|toast|omelette/)
              end

              breakfast_items.each_with_index do |item, item_index|
                create_menu_item(menu["id"], category["id"], item["id"], item_index * 10)
              end
            end

          when "Lunch Menu"
            lunch_categories = categories.select { |c| c["name"].downcase.include?("lunch") }

            # If no lunch-specific categories, add generic ones
            if lunch_categories.empty?
              lunch_categories = categories.select do |c|
                %w[appetizer salad sandwich side soup drink].any? do |word|
                  c["name"].downcase.include?(word)
                end
              end
            end

            lunch_categories.each_with_index do |category, index|
              add_category_to_menu(menu["id"], category["id"], index * 100)

              # Add lunch items
              lunch_items = items.select do |item|
                item["name"].downcase.match(/sandwich|salad|soup|wrap|burger|lunch/)
              end

              lunch_items.each_with_index do |item, item_index|
                create_menu_item(menu["id"], category["id"], item["id"], item_index * 10)
              end
            end

          when "Dinner Menu"
            # Add all categories to dinner menu
            categories.each_with_index do |category, index|
              add_category_to_menu(menu["id"], category["id"], index * 100)

              # Add items that fit this category
              dinner_items = items.select do |item|
                if category["name"].downcase.include?("appetizer")
                  item["name"].downcase.match(/appetizer|starter|dip|share|plate/)
                elsif category["name"].downcase.include?("entree") || category["name"].downcase.include?("main")
                  item["name"].downcase.match(/entree|steak|chicken|fish|pasta|dinner/)
                elsif category["name"].downcase.include?("side")
                  item["name"].downcase.match(/side|potato|vegetable|rice/)
                elsif category["name"].downcase.include?("dessert")
                  item["name"].downcase.match(/dessert|cake|pie|ice cream|sweet/)
                elsif category["name"].downcase.include?("drink")
                  item["name"].downcase.match(/drink|beverage|cocktail|wine|beer/)
                else
                  true # Add all items for other categories
                end
              end

              dinner_items.each_with_index do |item, item_index|
                create_menu_item(menu["id"], category["id"], item["id"], item_index * 10)
              end
            end

          when "Late Night Menu"
            late_night_categories = categories.select do |c|
              %w[appetizer dessert drink cocktail].any? do |word|
                c["name"].downcase.include?(word)
              end
            end

            late_night_categories.each_with_index do |category, index|
              add_category_to_menu(menu["id"], category["id"], index * 100)

              # Add late night items
              late_night_items = items.select do |item|
                item["name"].downcase.match(/appetizer|dessert|drink|cocktail|beer|wine|snack|small plate/)
              end

              late_night_items.each_with_index do |item, item_index|
                create_menu_item(menu["id"], category["id"], item["id"], item_index * 10)
              end
            end
          end
        end

        created_menus
      end

      def print_menu(menu_id, format = "text")
        logger.info "Generating menu #{menu_id} in #{format} format"

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
