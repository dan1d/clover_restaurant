# lib/clover_restaurant/services/table_service.rb
module CloverRestaurant
  module Services
    class TableService < BaseService
      def get_tables(limit = 100, offset = 0)
        logger.info "Fetching tables for merchant #{@config.merchant_id}"
        make_request(:get, endpoint("tables"), nil, { limit: limit, offset: offset })
      end

      def get_table(table_id)
        logger.info "Fetching table #{table_id} for merchant #{@config.merchant_id}"
        make_request(:get, endpoint("tables/#{table_id}"))
      end

      def create_table(table_data)
        logger.info "Creating new table for merchant #{@config.merchant_id}"
        make_request(:post, endpoint("tables"), table_data)
      end

      def update_table(table_id, table_data)
        logger.info "Updating table #{table_id} for merchant #{@config.merchant_id}"
        make_request(:post, endpoint("tables/#{table_id}"), table_data)
      end

      def delete_table(table_id)
        logger.info "Deleting table #{table_id} for merchant #{@config.merchant_id}"
        make_request(:delete, endpoint("tables/#{table_id}"))
      end

      def create_table_group(table_group_data)
        logger.info "Creating new table group for merchant #{@config.merchant_id}"
        make_request(:post, endpoint("table_groups"), table_group_data)
      end

      def get_table_groups(limit = 100, offset = 0)
        logger.info "Fetching table groups for merchant #{@config.merchant_id}"
        make_request(:get, endpoint("table_groups"), nil, { limit: limit, offset: offset })
      end

      def get_table_group(table_group_id)
        logger.info "Fetching table group #{table_group_id} for merchant #{@config.merchant_id}"
        make_request(:get, endpoint("table_groups/#{table_group_id}"))
      end

      def update_table_group(table_group_id, table_group_data)
        logger.info "Updating table group #{table_group_id} for merchant #{@config.merchant_id}"
        make_request(:post, endpoint("table_groups/#{table_group_id}"), table_group_data)
      end

      def delete_table_group(table_group_id)
        logger.info "Deleting table group #{table_group_id} for merchant #{@config.merchant_id}"
        make_request(:delete, endpoint("table_groups/#{table_group_id}"))
      end

      def assign_table_to_group(table_id, table_group_id)
        logger.info "Assigning table #{table_id} to group #{table_group_id}"
        update_table(table_id, { "tableGroup" => { "id" => table_group_id } })
      end

      def create_floor_plan(floor_plan_data)
        logger.info "Creating a new floor plan"
        make_request(:post, endpoint("floor_plans"), floor_plan_data)
      end

      def get_floor_plans(limit = 100, offset = 0)
        logger.info "Fetching floor plans for merchant #{@config.merchant_id}"
        make_request(:get, endpoint("floor_plans"), nil, { limit: limit, offset: offset })
      end

      def get_floor_plan(floor_plan_id)
        logger.info "Fetching floor plan #{floor_plan_id} for merchant #{@config.merchant_id}"
        make_request(:get, endpoint("floor_plans/#{floor_plan_id}"))
      end

      def update_floor_plan(floor_plan_id, floor_plan_data)
        logger.info "Updating floor plan #{floor_plan_id} for merchant #{@config.merchant_id}"
        make_request(:post, endpoint("floor_plans/#{floor_plan_id}"), floor_plan_data)
      end

      def delete_floor_plan(floor_plan_id)
        logger.info "Deleting floor plan #{floor_plan_id} for merchant #{@config.merchant_id}"
        make_request(:delete, endpoint("floor_plans/#{floor_plan_id}"))
      end

      def assign_order_to_table(order_id, table_id)
        logger.info "Assigning order #{order_id} to table #{table_id}"
        order_service = OrderService.new(@config)
        order_service.update_order(order_id, { "tables" => [{ "id" => table_id }] })
      end

      def get_table_status
        logger.info "Fetching table status for merchant #{@config.merchant_id}"

        tables = get_tables

        return nil unless tables && tables["elements"]

        table_status = {}

        tables["elements"].each do |table|
          table_id = table["id"]
          table_status[table_id] = {
            "name" => table["name"],
            "status" => "AVAILABLE",
            "orders" => []
          }
        end

        # Get orders with tables
        orders = make_request(:get, endpoint("orders"), nil, { filter: "tables!=null" })

        if orders && orders["elements"]
          orders["elements"].each do |order|
            next unless order["tables"] && order["tables"]["elements"]

            order["tables"]["elements"].each do |table|
              table_id = table["id"]

              next unless table_status[table_id]

              table_status[table_id]["status"] = "OCCUPIED"
              table_status[table_id]["orders"] << {
                "id" => order["id"],
                "createdTime" => order["createdTime"],
                "state" => order["state"]
              }
            end
          end
        end

        table_status
      end

      def create_standard_restaurant_layout(floor_plan_name = "Main Dining Room")
        logger.info "Creating standard restaurant layout"

        # Create a floor plan
        floor_plan = create_floor_plan({
                                         "name" => floor_plan_name
                                       })

        return nil unless floor_plan && floor_plan["id"]

        floor_plan_id = floor_plan["id"]

        # Define table groups
        table_groups_config = [
          { "name" => "Main Dining", "tables" => 20 },
          { "name" => "Bar Area", "tables" => 8 },
          { "name" => "Patio", "tables" => 10 },
          { "name" => "Private Room", "tables" => 5 }
        ]

        created_tables = []

        table_groups_config.each do |group_config|
          # Create table group
          table_group = create_table_group({
                                             "name" => group_config["name"],
                                             "floorPlan" => { "id" => floor_plan_id }
                                           })

          next unless table_group && table_group["id"]

          # Create tables for this group
          group_config["tables"].times do |i|
            table_number = i + 1
            table_name = "#{group_config["name"]} #{table_number}"

            table = create_table({
                                   "name" => table_name,
                                   "tableGroup" => { "id" => table_group["id"] },
                                   "floorPlan" => { "id" => floor_plan_id },
                                   "maxSeats" => [2, 4, 4, 6, 8].sample # Random seating capacity
                                 })

            created_tables << table if table && table["id"]
          end
        end

        # Return the created layout
        {
          "floorPlan" => floor_plan,
          "tables" => created_tables
        }
      end

      def merge_tables(table_ids, new_table_name = nil)
        logger.info "Merging tables: #{table_ids.join(", ")}"

        return false if table_ids.length < 2

        # Get first table to use as base
        base_table = get_table(table_ids.first)

        return false unless base_table

        # Generate merged table name if not provided
        new_table_name ||= "Merged #{base_table["name"]}"

        # Calculate max seats by summing all tables
        max_seats = 0

        table_ids.each do |table_id|
          table = get_table(table_id)
          max_seats += table["maxSeats"] if table && table["maxSeats"]
        end

        # Create new merged table
        merged_table = create_table({
                                      "name" => new_table_name,
                                      "maxSeats" => max_seats,
                                      "tableGroup" => base_table["tableGroup"],
                                      "floorPlan" => base_table["floorPlan"],
                                      "merged" => true,
                                      "mergedTables" => table_ids.map { |id| { "id" => id } }
                                    })

        # Hide original tables (but don't delete them)
        table_ids.each do |table_id|
          update_table(table_id, { "active" => false })
        end

        merged_table
      end

      def split_table(merged_table_id)
        logger.info "Splitting merged table #{merged_table_id}"

        merged_table = get_table(merged_table_id)

        return false unless merged_table && merged_table["merged"] && merged_table["mergedTables"]

        original_table_ids = merged_table["mergedTables"].map { |t| t["id"] }

        # Reactivate original tables
        original_table_ids.each do |table_id|
          update_table(table_id, { "active" => true })
        end

        # Delete the merged table
        delete_table(merged_table_id)

        true
      end
    end
  end
end
