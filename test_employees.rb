#!/usr/bin/env ruby
# add_employees.rb - Adds additional employees to the Clover account

# Add the local lib directory to the load path
$LOAD_PATH.unshift(File.expand_path("lib", __dir__))

require "clover_restaurant"
begin
  require "dotenv/load" # Load environment variables from .env file
rescue LoadError
  puts "dotenv gem not found, skipping .env file loading"
end

# Configure Clover
CloverRestaurant.configure do |config|
  config.merchant_id = ENV["CLOVER_MERCHANT_ID"] || raise("Please set CLOVER_MERCHANT_ID in .env file")
  config.api_token = ENV["CLOVER_API_TOKEN"] || raise("Please set CLOVER_API_TOKEN in .env file")
  config.environment = ENV["CLOVER_ENVIRONMENT"] || "https://sandbox.dev.clover.com/"
  config.log_level = ENV["LOG_LEVEL"] ? Logger.const_get(ENV["LOG_LEVEL"]) : Logger::INFO
end

# Initialize the employee service
employee_service = CloverRestaurant::Services::EmployeeService.new

# First, ensure we have the necessary roles
puts "Creating standard restaurant roles..."
roles = employee_service.create_standard_restaurant_roles

if roles && !roles.empty?
  puts "✅ Created #{roles.size} standard roles"
else
  puts "❌ Failed to create roles, cannot create employees"
  exit 1
end

# Create a fixed number of employees
num_employees = 10
puts "Creating #{num_employees} restaurant employees..."

# Fixed employee data for predictable results
employees_data = [
  { name: "John Manager", role_name: "Manager", pin: "1111" },
  { name: "Mary Server", role_name: "Server", pin: "2222" },
  { name: "Bob Bartender", role_name: "Bartender", pin: "3333" },
  { name: "Alice Host", role_name: "Host", pin: "4444" },
  { name: "Charlie Cook", role_name: "Kitchen Staff", pin: "5555" },
  { name: "David Manager", role_name: "Manager", pin: "6666" },
  { name: "Sarah Server", role_name: "Server", pin: "7777" },
  { name: "Jake Bartender", role_name: "Bartender", pin: "8888" },
  { name: "Emily Host", role_name: "Host", pin: "9999" },
  { name: "Mike Cook", role_name: "Kitchen Staff", pin: "1010" }
]

# Find role IDs
role_map = {}
roles.each do |role|
  role_map[role["name"]] = role["id"]
end

created_employees = []

employees_data.each_with_index do |emp_data, index|
  role_id = role_map[emp_data[:role_name]] || role_map["Server"] # Default to server
  next unless role_id

  # Prepare employee data
  first_name, last_name = emp_data[:name].split(" ", 2)

  employee_data = {
    "name" => emp_data[:name],
    "nickname" => first_name,
    "customId" => "EMP#{index + 100}",
    "pin" => emp_data[:pin],
    "roles" => [{ "id" => role_id }],
    "inviteSent" => false,
    "isOwner" => false
  }

  puts "Creating employee: #{employee_data["name"]} (#{emp_data[:role_name]})"

  begin
    # Check if employee already exists by PIN
    existing_employee = employee_service.get_employee_by_pin(emp_data[:pin])

    if existing_employee
      puts "Employee with PIN #{emp_data[:pin]} already exists, skipping creation"
      created_employees << existing_employee
      next
    end

    employee = employee_service.create_employee(employee_data)

    if employee && employee["id"]
      puts "✅ Successfully created employee with ID: #{employee["id"]}"
      created_employees << employee
    else
      puts "❌ Error creating employee"
    end
  rescue StandardError => e
    puts "❌ Error: #{e.message}"
  end
end

puts "Created #{created_employees.size} employees"
