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
        logger.info "=== Checking if employee '#{employee_data["name"]}' already exists ==="

        existing_employees = get_employees
        if existing_employees && existing_employees["elements"]
          existing_employee = existing_employees["elements"].find do |emp|
            emp["name"] == employee_data["name"]
          end

          if existing_employee
            logger.info "Employee '#{employee_data["name"]}' already exists with ID: #{existing_employee["id"]}, skipping creation."
            return existing_employee
          end
        end

        # Ensure role is set correctly
        if employee_data["role"].is_a?(Hash) && employee_data["role"]["id"].is_a?(String)
          # Ensure roles are formatted correctly
          employee_data["roles"] = [{ "id" => employee_data["role"]["id"] }]
        else
          logger.info "=== Fetching available roles ==="
          available_roles = get_roles
          if available_roles && available_roles["elements"]
            employee_role = available_roles["elements"].find { |r| r["name"] == "Employee" }
          end

          if employee_role.nil?
            logger.error "❌ No valid 'Employee' role found! Cannot create employees."
            return nil
          end

          # Correctly set the role ID as an array
          employee_data["roles"] = [{ "id" => employee_role["id"] }]
        end

        # Remove 'role' field as it's not used in Clover API request
        employee_data.delete("role")

        # Remove 'pin' field (if necessary)
        employee_data.delete("pin")

        logger.info "Creating new employee: #{employee_data.inspect}"
        response = make_request(:post, endpoint("employees"), employee_data)

        if response && response["id"]
          logger.info "✅ Successfully created employee '#{response["name"]}' with ID: #{response["id"]}"
        else
          logger.error "❌ ERROR: Employee creation failed. Response: #{response.inspect}"
          return nil # Stop execution if employee creation fails
        end

        response
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

        # Check if role with the same name already exists
        existing_roles = get_roles
        if existing_roles && existing_roles["elements"]
          existing_role = existing_roles["elements"].find { |r| r["name"] == role_data["name"] }
          if existing_role
            logger.info "Role '#{role_data["name"]}' already exists with ID: #{existing_role["id"]}, skipping creation"
            return existing_role
          end
        end

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

        # Check if employee already has this role
        employee = get_employee(employee_id)
        if employee && employee["role"] && employee["role"]["id"] == role_id
          logger.info "Employee #{employee_id} already has role #{role_id}, skipping assignment"
          return true
        end

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

        # Check if a similar shift already exists
        if shift_data["employee"] && shift_data["employee"]["id"] && shift_data["inTime"]
          employee_id = shift_data["employee"]["id"]
          in_time = shift_data["inTime"]

          # Get existing shifts for this employee
          shifts = get_employee_shifts(employee_id)

          if shifts && shifts["elements"]
            # Check for shifts with similar in times (within 15 minutes)
            fifteen_minutes_ms = 15 * 60 * 1000
            existing_shift = shifts["elements"].find do |shift|
              shift["inTime"] && (shift["inTime"] - in_time).abs < fifteen_minutes_ms
            end

            if existing_shift
              logger.info "Similar shift already exists for employee #{employee_id} with ID: #{existing_shift["id"]}, skipping creation"
              return existing_shift
            end
          end
        end

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

        # Check if employee is already clocked in
        shifts = get_employee_shifts(employee_id)
        if shifts && shifts["elements"]
          active_shift = shifts["elements"].find { |shift| shift["inTime"] && !shift["outTime"] }
          if active_shift
            logger.info "Employee #{employee_id} already has an active shift with ID: #{active_shift["id"]}, skipping clock-in"
            return active_shift
          end
        end

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

        # Check if shift is already clocked out
        shift = get_shift(shift_id)
        if shift && shift["outTime"]
          logger.info "Shift #{shift_id} is already clocked out, skipping"
          return shift
        end

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

        # Check for existing roles first
        existing_roles = get_roles
        if existing_roles && existing_roles["elements"] && existing_roles["elements"].size >= 3
          standard_names = ["Manager", "Server", "Bartender", "Host", "Kitchen Staff"]

          existing_standard = existing_roles["elements"].select { |r| standard_names.include?(r["name"]) }

          if existing_standard.size >= 3
            logger.info "Found #{existing_standard.size} standard roles already existing, skipping creation"
            return existing_standard
          end
        end

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

      def create_random_employees(count = 15, roles = nil)
        logger.info "Creating #{count} random employees"

        # Get roles if not provided
        roles ||= get_roles
        return [] unless roles && !roles.empty?

        # Define realistic employee data
        first_names = [
          "James", "Mary", "John", "Patricia", "Robert", "Jennifer", "Michael", "Linda",
          "William", "Elizabeth", "David", "Barbara", "Richard", "Susan", "Joseph", "Jessica",
          "Thomas", "Sarah", "Charles", "Karen", "Christopher", "Nancy", "Daniel", "Lisa",
          "Matthew", "Betty", "Anthony", "Margaret", "Mark", "Sandra", "Donald", "Ashley",
          "Steven", "Kimberly", "Paul", "Emily", "Andrew", "Donna", "Joshua", "Michelle"
        ]

        last_names = [
          "Smith", "Johnson", "Williams", "Brown", "Jones", "Garcia", "Miller", "Davis",
          "Rodriguez", "Martinez", "Hernandez", "Lopez", "Gonzalez", "Wilson", "Anderson",
          "Thomas", "Taylor", "Moore", "Jackson", "Martin", "Lee", "Perez", "Thompson",
          "White", "Harris", "Sanchez", "Clark", "Ramirez", "Lewis", "Robinson", "Walker"
        ]

        # Define shifts
        shifts = [
          { name: "Morning", start: "06:00", end: "14:00" },
          { name: "Afternoon", start: "14:00", end: "22:00" },
          { name: "Evening", start: "16:00", end: "00:00" },
          { name: "Night", start: "22:00", end: "06:00" }
        ]

        created_employees = []

        # Create employees with appropriate role distribution
        count.times do |i|
          # Select role based on position in restaurant
          role = if i == 0
                  # First employee is always a manager
                  roles.find { |r| r["name"] == "Restaurant Manager" }
                elsif i == 1
                  # Second employee is a shift supervisor
                  roles.find { |r| r["name"] == "Shift Supervisor" }
                else
                  # Other employees are distributed among remaining roles
                  remaining_roles = roles.reject { |r| ["Restaurant Manager", "Shift Supervisor"].include?(r["name"]) }
                  remaining_roles.sample
                end

          # Generate employee data
          first_name = first_names.sample
          last_name = last_names.sample
          pin = rand(1000..9999).to_s
          shift = shifts.sample

          employee_data = {
            "name" => "#{first_name} #{last_name}",
            "nickname" => first_name,
            "pin" => pin,
            "role" => { "id" => role["id"] },
            "shifts" => [
              {
                "name" => shift[:name],
                "startTime" => shift[:start],
                "endTime" => shift[:end]
              }
            ],
            "isOwner" => false
          }

          # Create the employee
          employee = create_employee(employee_data)
          if employee && employee["id"]
            logger.info "✅ Created #{role["name"]}: #{employee["name"]}"
            created_employees << employee
          else
            logger.error "❌ Failed to create employee: #{employee_data["name"]}"
          end
        end

        created_employees
      end
    end
  end
end
