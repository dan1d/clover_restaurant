# lib/clover_restaurant/services/table_service.rb
module CloverRestaurant
  module Services
    class TableService < BaseService
      def get_tables(limit = 100, offset = 0)
        logger.info "=== Fetching tables for merchant #{@config.merchant_id} ==="
        make_request(:get, endpoint("tables"), nil, { limit: limit, offset: offset })
      end

      def get_table(table_id)
        logger.info "=== Fetching table #{table_id} for merchant #{@config.merchant_id} ==="
        make_request(:get, endpoint("tables/#{table_id}"))
      end

      def create_table(table_data)
        logger.info "=== Creating new table for merchant #{@config.merchant_id} ==="

        # Check if table with the same name already exists
        existing_tables = get_tables
        if existing_tables && existing_tables["elements"]
          existing_table = existing_tables["elements"].find { |t| t["name"] == table_data["name"] }
          if existing_table
            logger.info "Table '#{table_data["name"]}' already exists with ID: #{existing_table["id"]}, skipping creation"
            return existing_table
          end
        end

        logger.info "Table data: #{table_data.inspect}"
        make_request(:post, endpoint("tables"), table_data)
      end

      def update_table(table_id, table_data)
        logger.info "=== Updating table #{table_id} for merchant #{@config.merchant_id} ==="
        logger.info "Update data: #{table_data.inspect}"
        make_request(:post, endpoint("tables/#{table_id}"), table_data)
      end

      def delete_table(table_id)
        logger.info "=== Deleting table #{table_id} for merchant #{@config.merchant_id} ==="
        make_request(:delete, endpoint("tables/#{table_id}"))
      end

      def create_table_group(table_group_data)
        logger.info "=== Creating new table group for merchant #{@config.merchant_id} ==="

        # Check if table group with the same name already exists
        existing_groups = get_table_groups
        if existing_groups && existing_groups["elements"]
          existing_group = existing_groups["elements"].find { |g| g["name"] == table_group_data["name"] }
          if existing_group
            logger.info "Table group '#{table_group_data["name"]}' already exists with ID: #{existing_group["id"]}, skipping creation"
            return existing_group
          end
        end

        logger.info "Table group data: #{table_group_data.inspect}"
        make_request(:post, endpoint("table_groups"), table_group_data)
      end

      def get_table_groups(limit = 100, offset = 0)
        logger.info "=== Fetching table groups for merchant #{@config.merchant_id} ==="
        make_request(:get, endpoint("table_groups"), nil, { limit: limit, offset: offset })
      end

      def get_table_group(table_group_id)
        logger.info "=== Fetching table group #{table_group_id} for merchant #{@config.merchant_id} ==="
        make_request(:get, endpoint("table_groups/#{table_group_id}"))
      end

      def update_table_group(table_group_id, table_group_data)
        logger.info "=== Updating table group #{table_group_id} for merchant #{@config.merchant_id} ==="
        logger.info "Update data: #{table_group_data.inspect}"
        make_request(:post, endpoint("table_groups/#{table_group_id}"), table_group_data)
      end

      def delete_table_group(table_group_id)
        logger.info "=== Deleting table group #{table_group_id} for merchant #{@config.merchant_id} ==="
        make_request(:delete, endpoint("table_groups/#{table_group_id}"))
      end

      def assign_table_to_group(table_id, table_group_id)
        logger.info "=== Assigning table #{table_id} to group #{table_group_id} ==="

        # Check if table already belongs to this group
        table = get_table(table_id)
        if table && table["tableGroup"] && table["tableGroup"]["id"] == table_group_id
          logger.info "Table #{table_id} already belongs to group #{table_group_id}, skipping assignment"
          return table
        end

        update_table(table_id, { "tableGroup" => { "id" => table_group_id } })
      end

      def create_floor_plan(floor_plan_data)
        logger.info "=== Creating a new floor plan ==="

        # Check if floor plan with the same name already exists
        existing_plans = get_floor_plans
        if existing_plans && existing_plans["elements"]
          existing_plan = existing_plans["elements"].find { |p| p["name"] == floor_plan_data["name"] }
          if existing_plan
            logger.info "Floor plan '#{floor_plan_data["name"]}' already exists with ID: #{existing_plan["id"]}, skipping creation"
            return existing_plan
          end
        end

        logger.info "Floor plan data: #{floor_plan_data.inspect}"
        make_request(:post, endpoint("floor_plans"), floor_plan_data)
      end

      def get_floor_plans(limit = 100, offset = 0)
        logger.info "=== Fetching floor plans for merchant #{@config.merchant_id} ==="
        make_request(:get, endpoint("floor_plans"), nil, { limit: limit, offset: offset })
      end

      def get_floor_plan(floor_plan_id)
        logger.info "=== Fetching floor plan #{floor_plan_id} for merchant #{@config.merchant_id} ==="
        make_request(:get, endpoint("floor_plans/#{floor_plan_id}"))
      end

      def update_floor_plan(floor_plan_id, floor_plan_data)
        logger.info "=== Updating floor plan #{floor_plan_id} for merchant #{@config.merchant_id} ==="
        logger.info "Update data: #{floor_plan_data.inspect}"
        make_request(:post, endpoint("floor_plans/#{floor_plan_id}"), floor_plan_data)
      end

      def delete_floor_plan(floor_plan_id)
        logger.info "=== Deleting floor plan #{floor_plan_id} for merchant #{@config.merchant_id} ==="
        make_request(:delete, endpoint("floor_plans/#{floor_plan_id}"))
      end

      def assign_order_to_table(order_id, table_id)
        logger.info "=== Assigning order #{order_id} to table #{table_id} ==="

        # Check if order is already assigned to this table
        order_service = OrderService.new(@config)
        order = order_service.get_order(order_id)

        if order && order["tables"] && order["tables"]["elements"] && order["tables"]["elements"].any? do |t|
          t["id"] == table_id
        end
          logger.info "Order #{order_id} is already assigned to table #{table_id}, skipping assignment"
          return order
        end

        order_service.update_order(order_id, { "tables" => [{ "id" => table_id }] })
      end

      def get_table_status
        logger.info "=== Fetching table status for merchant #{@config.merchant_id} ==="

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
        logger.info "=== Creating standard restaurant layout ==="

        # Check if floor plan already exists
        existing_plans = get_floor_plans
        if existing_plans && existing_plans["elements"]
          existing_plan = existing_plans["elements"].find { |p| p["name"] == floor_plan_name }
          if existing_plan
            logger.info "Floor plan '#{floor_plan_name}' already exists with ID: #{existing_plan["id"]}"

            # Check if tables already exist for this floor plan
            existing_tables = get_tables
            if existing_tables && existing_tables["elements"] && !existing_tables["elements"].empty?
              floor_plan_tables = existing_tables["elements"].select do |t|
                t["floorPlan"] && t["floorPlan"]["id"] == existing_plan["id"]
              end

              if floor_plan_tables.size >= 10
                logger.info "Found #{floor_plan_tables.size} tables for floor plan '#{floor_plan_name}', skipping creation"
                return {
                  "floorPlan" => existing_plan,
                  "tables" => floor_plan_tables
                }
              end
            end
          end
        end

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
        success_count = 0
        error_count = 0

        table_groups_config.each_with_index do |group_config, group_index|
          logger.info "Creating table group #{group_index + 1}/#{table_groups_config.size}: #{group_config["name"]}"

          # Create table group
          table_group = create_table_group({
                                             "name" => group_config["name"],
                                             "floorPlan" => { "id" => floor_plan_id }
                                           })

          next unless table_group && table_group["id"]

          logger.info "Successfully created table group: #{table_group["name"]} with ID: #{table_group["id"]}"

          # Create tables for this group
          group_config["tables"].times do |i|
            table_number = i + 1
            table_name = "#{group_config["name"]} #{table_number}"

            # Use deterministic seating capacity based on table number
            seating_options = [2, 4, 4, 6, 8]
            max_seats = seating_options[i % seating_options.size]

            logger.info "Creating table #{table_name} with capacity #{max_seats}"

            begin
              table = create_table({
                                     "name" => table_name,
                                     "tableGroup" => { "id" => table_group["id"] },
                                     "floorPlan" => { "id" => floor_plan_id },
                                     "maxSeats" => max_seats
                                   })

              if table && table["id"]
                logger.info "Successfully created table: #{table["name"]} with ID: #{table["id"]}"
                created_tables << table
                success_count += 1
              else
                logger.warn "Created table but received unexpected response: #{table.inspect}"
                error_count += 1
              end
            rescue StandardError => e
              logger.error "Failed to create table #{table_name}: #{e.message}"
              error_count += 1
            end
          end
        end

        logger.info "=== Finished creating tables: #{success_count} successful, #{error_count} failed ==="

        # Return the created layout
        {
          "floorPlan" => floor_plan,
          "tables" => created_tables
        }
      end

      def merge_tables(table_ids, new_table_name = nil)
        logger.info "=== Merging tables: #{table_ids.join(", ")} ==="

        return false if table_ids.length < 2

        # Check if merged table already exists
        if new_table_name
          existing_tables = get_tables
          if existing_tables && existing_tables["elements"]
            existing_merged = existing_tables["elements"].find do |t|
              t["name"] == new_table_name && t["merged"] == true
            end
            if existing_merged
              logger.info "Merged table '#{new_table_name}' already exists with ID: #{existing_merged["id"]}, skipping creation"
              return existing_merged
            end
          end
        end

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
        logger.info "=== Splitting merged table #{merged_table_id} ==="

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
