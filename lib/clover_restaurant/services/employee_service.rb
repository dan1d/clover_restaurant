# lib/clover_restaurant/services/employee_service.rb
module CloverRestaurant
  module Services
    class EmployeeService < BaseService
      def get_employees(limit = 100, offset = 0, filter = nil)
        logger.info "=== Fetching employees for merchant #{@config.merchant_id} ==="
        query_params = { limit: limit, offset: offset }
        query_params[:filter] = filter if filter

        make_request(:get, endpoint("employees"), nil, query_params)
      end

      def get_employee(employee_id)
        logger.info "=== Fetching employee #{employee_id} for merchant #{@config.merchant_id} ==="
        make_request(:get, endpoint("employees/#{employee_id}"))
      end

      def create_employee(employee_data)
        logger.info "=== Creating new employee for merchant #{@config.merchant_id} ==="
        logger.info "Employee data: #{employee_data.inspect}"
        make_request(:post, endpoint("employees"), employee_data)
      end

      def update_employee(employee_id, employee_data)
        logger.info "=== Updating employee #{employee_id} for merchant #{@config.merchant_id} ==="
        logger.info "Update data: #{employee_data.inspect}"
        make_request(:post, endpoint("employees/#{employee_id}"), employee_data)
      end

      def delete_employee(employee_id)
        logger.info "=== Deleting employee #{employee_id} for merchant #{@config.merchant_id} ==="
        make_request(:delete, endpoint("employees/#{employee_id}"))
      end

      def get_roles(limit = 100, offset = 0)
        logger.info "=== Fetching employee roles for merchant #{@config.merchant_id} ==="
        make_request(:get, endpoint("roles"), nil, { limit: limit, offset: offset })
      end

      def get_role(role_id)
        logger.info "=== Fetching role #{role_id} for merchant #{@config.merchant_id} ==="
        make_request(:get, endpoint("roles/#{role_id}"))
      end

      def create_role(role_data)
        logger.info "=== Creating new role for merchant #{@config.merchant_id} ==="

        # IMPORTANT: Add systemRole field if not present
        unless role_data.has_key?("systemRole")
          # Use "EMPLOYEE" as default systemRole if not specified
          role_data["systemRole"] = role_data["systemRole"] || "EMPLOYEE"
          logger.info "Added required systemRole field: #{role_data["systemRole"]}"
        end

        logger.info "Role data: #{role_data.inspect}"
        make_request(:post, endpoint("roles"), role_data)
      end

      def update_role(role_id, role_data)
        logger.info "=== Updating role #{role_id} for merchant #{@config.merchant_id} ==="

        # IMPORTANT: Add systemRole field if not present
        unless role_data.has_key?("systemRole")
          # Try to get the existing role to maintain its systemRole value
          begin
            existing_role = get_role(role_id)
            if existing_role && existing_role["systemRole"]
              role_data["systemRole"] = existing_role["systemRole"]
              logger.info "Using existing systemRole value: #{role_data["systemRole"]}"
            else
              role_data["systemRole"] = "EMPLOYEE"
              logger.info "Added default systemRole field: #{role_data["systemRole"]}"
            end
          rescue StandardError => e
            # If we can't get the existing role, use a default
            role_data["systemRole"] = "EMPLOYEE"
            logger.info "Added default systemRole field: #{role_data["systemRole"]}"
          end
        end

        logger.info "Update data: #{role_data.inspect}"
        make_request(:post, endpoint("roles/#{role_id}"), role_data)
      end

      def delete_role(role_id)
        logger.info "=== Deleting role #{role_id} for merchant #{@config.merchant_id} ==="
        make_request(:delete, endpoint("roles/#{role_id}"))
      end

      def assign_role_to_employee(employee_id, role_id)
        logger.info "=== Assigning role #{role_id} to employee #{employee_id} ==="
        payload = {
          "role" => { "id" => role_id }
        }
        logger.info "Request payload: #{payload.inspect}"
        make_request(:post, endpoint("employees/#{employee_id}/roles"), payload)
      end

      def get_employee_shifts(employee_id, limit = 50, offset = 0)
        logger.info "=== Fetching shifts for employee #{employee_id} ==="
        make_request(:get, endpoint("employees/#{employee_id}/shifts"), nil, { limit: limit, offset: offset })
      end

      def create_shift(shift_data)
        logger.info "=== Creating new shift ==="
        logger.info "Shift data: #{shift_data.inspect}"
        make_request(:post, endpoint("shifts"), shift_data)
      end

      def get_shift(shift_id)
        logger.info "=== Fetching shift #{shift_id} ==="
        make_request(:get, endpoint("shifts/#{shift_id}"))
      end

      def update_shift(shift_id, shift_data)
        logger.info "=== Updating shift #{shift_id} ==="
        logger.info "Update data: #{shift_data.inspect}"
        make_request(:post, endpoint("shifts/#{shift_id}"), shift_data)
      end

      def delete_shift(shift_id)
        logger.info "=== Deleting shift #{shift_id} ==="
        make_request(:delete, endpoint("shifts/#{shift_id}"))
      end

      def clock_in(employee_id)
        logger.info "=== Clocking in employee #{employee_id} ==="
        current_time = Time.now.to_i * 1000 # Milliseconds since epoch

        shift_data = {
          "employee" => { "id" => employee_id },
          "inTime" => current_time
        }

        logger.info "Clock-in data: #{shift_data.inspect}"
        create_shift(shift_data)
      end

      def clock_out(shift_id)
        logger.info "=== Clocking out shift #{shift_id} ==="
        current_time = Time.now.to_i * 1000 # Milliseconds since epoch

        shift_data = {
          "outTime" => current_time
        }

        logger.info "Clock-out data: #{shift_data.inspect}"
        update_shift(shift_id, shift_data)
      end

      def get_employee_by_pin(pin)
        logger.info "=== Looking up employee by PIN #{pin} ==="
        employees = get_employees

        return nil unless employees && employees["elements"]

        employee = employees["elements"].find { |emp| emp["pin"] == pin.to_s }

        if employee
          logger.info "Found employee: #{employee["name"]} (ID: #{employee["id"]})"
        else
          logger.info "No employee found with PIN: #{pin}"
        end

        employee
      end

      def create_standard_restaurant_roles
        logger.info "=== Creating standard restaurant roles ==="

        standard_roles = [
          {
            "name" => "Manager",
            "systemRole" => "MANAGER",
            "permissions" => %w[
              ADMIN
              MERCHANT_R
              MERCHANT_W
              ORDERS_R
              ORDERS_W
              INVENTORY_R
              INVENTORY_W
              PAYMENTS_R
              PAYMENTS_W
              EMPLOYEES_R
              EMPLOYEES_W
            ]
          },
          {
            "name" => "Server",
            "systemRole" => "EMPLOYEE",
            "permissions" => %w[
              ORDERS_R
              ORDERS_W
              INVENTORY_R
              PAYMENTS_R
              PAYMENTS_W
            ]
          },
          {
            "name" => "Bartender",
            "systemRole" => "EMPLOYEE",
            "permissions" => %w[
              ORDERS_R
              ORDERS_W
              INVENTORY_R
              PAYMENTS_R
              PAYMENTS_W
            ]
          },
          {
            "name" => "Host",
            "systemRole" => "EMPLOYEE",
            "permissions" => %w[
              ORDERS_R
              CUSTOMERS_R
              CUSTOMERS_W
            ]
          },
          {
            "name" => "Kitchen Staff",
            "systemRole" => "EMPLOYEE",
            "permissions" => [
              "ORDERS_R"
            ]
          }
        ]

        created_roles = []
        success_count = 0
        error_count = 0

        standard_roles.each_with_index do |role_data, index|
          logger.info "Creating role #{index + 1}/#{standard_roles.size}: #{role_data["name"]}"

          begin
            role = create_role(role_data)
            if role && role["id"]
              logger.info "Successfully created role: #{role["name"]} with ID: #{role["id"]}"
              created_roles << role
              success_count += 1
            else
              logger.warn "Created role but received unexpected response: #{role.inspect}"
              error_count += 1
            end
          rescue StandardError => e
            logger.error "Failed to create role #{role_data["name"]}: #{e.message}"
            error_count += 1
          end
        end

        logger.info "=== Finished creating roles: #{success_count} successful, #{error_count} failed ==="
        created_roles
      end

      def create_random_employees(num_employees = 5, roles = nil)
        logger.info "=== Creating #{num_employees} random employees ==="

        # Get roles first if not provided
        if roles.nil? || roles.empty?
          logger.info "No roles provided, fetching available roles"
          roles_response = get_roles

          roles = if roles_response && roles_response["elements"] && !roles_response["elements"].empty?
                    roles_response["elements"]
                  else
                    # Create standard roles
                    logger.info "No existing roles found, creating standard roles"
                    create_standard_restaurant_roles
                  end
        end

        if roles.nil? || roles.empty?
          logger.error "No roles available to assign to employees"
          return []
        end

        logger.info "Found #{roles.size} available roles"

        created_employees = []
        success_count = 0
        error_count = 0

        job_titles = {
          "Manager" => ["General Manager", "Assistant Manager", "Shift Manager"],
          "Server" => %w[Server Waiter Waitress],
          "Bartender" => ["Bartender", "Bar Manager", "Mixologist"],
          "Host" => ["Host", "Hostess", "Front of House"],
          "Kitchen Staff" => ["Chef", "Line Cook", "Sous Chef", "Dishwasher", "Prep Cook"]
        }

        num_employees.times do |i|
          # Generate random 4-digit PIN
          pin = rand(1000..9999).to_s

          # Select random role
          role = roles.sample

          # Generate name
          first_name = "FirstName#{i + 1}" # Using predictable names instead of Faker
          last_name = "LastName#{i + 1}"

          # Determine job title based on role name
          role_name = role["name"]
          title = if job_titles.key?(role_name)
                    job_titles[role_name].sample
                  else
                    role_name
                  end

          employee_data = {
            "name" => "#{first_name} #{last_name}",
            "nickname" => first_name,
            "customId" => "EMP#{i + 100}",
            "pin" => pin,
            "role" => { "id" => role["id"] },
            "inviteSent" => false,
            "isOwner" => false
          }

          logger.info "Creating employee #{i + 1}/#{num_employees}: #{first_name} #{last_name} (Role: #{role_name})"

          begin
            employee = create_employee(employee_data)

            if employee && employee["id"]
              logger.info "Successfully created employee with ID: #{employee["id"]}"

              # Assign role to employee
              begin
                logger.info "Assigning role #{role["name"]} to employee"
                assign_role_to_employee(employee["id"], role["id"])
                logger.info "Successfully assigned role"
              rescue StandardError => e
                logger.error "Failed to assign role to employee: #{e.message}"
              end

              created_employees << employee
              success_count += 1
            else
              logger.warn "Created employee but received unexpected response: #{employee.inspect}"
              error_count += 1
            end
          rescue StandardError => e
            logger.error "Failed to create employee: #{e.message}"
            error_count += 1
          end
        end

        logger.info "=== Finished creating employees: #{success_count} successful, #{error_count} failed ==="
        created_employees
      end
    end
  end
end
