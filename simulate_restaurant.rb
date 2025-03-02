#!/usr/bin/env ruby
# simulate_restaurant.rb - Runs a restaurant simulation with orders and payments
# Generates analytics and exports results.

# Add the local lib directory to the load path
$LOAD_PATH.unshift(File.expand_path("lib", __dir__))

require "clover_restaurant"
begin
  require "dotenv/load" # Load environment variables from .env file
rescue LoadError
  puts "dotenv gem not found, skipping .env file loading"
end

require "date"
require "terminal-table"
require "colorize"
require "active_support/time"
require "optparse"
require "json"
require "csv"
require "fileutils"
require "set"

class RestaurantSimulator
  attr_reader :options, :restaurant_generator, :results, :services_manager

  def initialize
    @options = parse_options
    configure_clover
    @services_manager = CloverRestaurant.services
    @restaurant_generator = CloverRestaurant::DataGeneration::RestaurantGenerator.new
    @results = { summary: {} }
  end

  def run
    display_header
    setup_restaurant
    simulate_days
    generate_analytics
    display_results
    export_results if options[:export]
  end

  private

  def parse_options
    options = {
      name: ENV["RESTAURANT_NAME"] || "Claude's Bistro",
      days: (ENV["SIMULATION_DAYS"] || "10").to_i, # Simulate last 10 days by default
      start_date: Date.parse(ENV["START_DATE"] || (Date.today - 10).to_s), # Start from 10 days ago
      export: ENV["EXPORT_RESULTS"]&.downcase == "true",
      export_format: ENV["EXPORT_FORMAT"]&.downcase || "json",
      export_dir: ENV["EXPORT_DIR"] || "./reports",
      verify_categories: ENV["VERIFY_CATEGORIES"]&.downcase == "true" || true
    }

    OptionParser.new do |opts|
      opts.banner = "Usage: simulate_restaurant.rb [options]"

      opts.on("-n", "--name NAME", "Restaurant name") { |name| options[:name] = name }
      opts.on("-d", "--days DAYS", Integer, "Number of days to simulate") { |days| options[:days] = days }
      opts.on("-s", "--start-date DATE", "Start date (YYYY-MM-DD)") { |date| options[:start_date] = Date.parse(date) }
      opts.on("-e", "--[no-]export", "Export results to files") { |export| options[:export] = export }
      opts.on("-f", "--format FORMAT", "Export format (json, csv)") do |format|
        options[:export_format] = format.downcase
      end
      opts.on("-o", "--output-dir DIR", "Directory for exported files") { |dir| options[:export_dir] = dir }
      opts.on("-v", "--verbose", "Run with verbose output") do
        options[:verbose] = true
        ENV["LOG_LEVEL"] = "DEBUG"
      end
      opts.on("--[no-]verify-categories", "Verify and fix category assignments") do |verify|
        options[:verify_categories] = verify
      end
      opts.on("-h", "--help", "Show this help message") do
        puts opts
        exit
      end
    end.parse!

    options
  end

  def configure_clover
    CloverRestaurant.configure do |config|
      config.merchant_id = ENV["CLOVER_MERCHANT_ID"] || raise("Please set CLOVER_MERCHANT_ID in .env file")
      config.api_token = ENV["CLOVER_API_TOKEN"] || raise("Please set CLOVER_API_TOKEN in .env file")
      config.environment = ENV["CLOVER_ENVIRONMENT"] || "https://sandbox.dev.clover.com/"
      config.log_level = ENV["LOG_LEVEL"] ? Logger.const_get(ENV["LOG_LEVEL"]) : Logger::INFO
    end
  end

  def display_header
    puts "\n#{"=" * 80}".colorize(:cyan)
    puts "#{"RESTAURANT SIMULATION".center(80)}".colorize(:cyan)
    puts "#{"=" * 80}\n".colorize(:cyan)

    puts "Simulating #{options[:days]} days of operation for: #{options[:name]}".colorize(:yellow)
    puts "Starting from: #{options[:start_date]}"
    puts "Merchant ID: #{ENV["CLOVER_MERCHANT_ID"]}"
    puts "Environment: #{ENV["CLOVER_ENVIRONMENT"]}"
    puts "Exporting results: #{options[:export] ? "Yes (#{options[:export_format].upcase})" : "No"}"
    puts "Verify category assignments: #{options[:verify_categories] ? "Yes" : "No"}"
  end

  def setup_restaurant
    puts "\nSetting up restaurant...".colorize(:light_blue)

    # Try to update the restaurant name
    begin
      @services_manager.merchant.update_merchant_property("name", options[:name])
      puts "✅ Restaurant name updated to: #{options[:name]}"
    rescue StandardError => e
      puts "⚠️ Warning: Could not update restaurant name: #{e.message}"
    end

    # Ensure we have enough employees
    ensure_employees_exist

    # Ensure we have categories and items
    verify_category_assignments if options[:verify_categories]

    # Check for other required entities
    ensure_other_entities

    puts "✅ Restaurant setup complete"
  rescue StandardError => e
    puts "\nERROR during restaurant setup: #{e.message}".colorize(:red)
    puts e.backtrace.join("\n").colorize(:red) if options[:verbose]
    exit 1
  end

  def ensure_employees_exist
    puts "\nChecking restaurant employees...".colorize(:light_blue)

    # First, ensure we have the necessary roles
    begin
      puts "Creating standard restaurant roles..."
      roles = @services_manager.employee.create_standard_restaurant_roles

      if roles && !roles.empty?
        puts "✅ Found #{roles.size} roles"
      else
        puts "⚠️ Warning: No roles found, may use default roles"
      end
    rescue StandardError => e
      puts "⚠️ Warning: Error checking roles: #{e.message}"
      puts "Continuing with existing roles..."
    end

    # Check existing employees
    begin
      existing_employees = @services_manager.employee.get_employees
      employee_count = existing_employees && existing_employees["elements"] ? existing_employees["elements"].size : 0
      puts "Found #{employee_count} existing employees"

      # Only create more employees if we have fewer than 5
      if employee_count >= 5
        puts "✅ Sufficient employees exist (#{employee_count})"
        return
      end
    rescue StandardError => e
      puts "⚠️ Warning: Error checking employees: #{e.message}"
      puts "Will attempt to create some employees..."
      employee_count = 0
    end

    # Fixed employee data for predictable results
    employees_data = [
      { name: "John Manager", role_name: "Manager", pin: "1111" },
      { name: "Mary Server", role_name: "Server", pin: "2222" },
      { name: "Bob Bartender", role_name: "Bartender", pin: "3333" },
      { name: "Alice Host", role_name: "Host", pin: "4444" },
      { name: "Charlie Cook", role_name: "Kitchen Staff", pin: "5555" }
    ]

    # Only create the employees we need
    num_to_create = [5 - employee_count, 5].min
    return if num_to_create <= 0

    puts "Creating #{num_to_create} new employees..."
    created_count = 0

    employees_data.first(num_to_create).each do |emp_data|
      employee_data = {
        "name" => emp_data[:name],
        "nickname" => emp_data[:name].split(" ").first,
        "pin" => emp_data[:pin]
      }

      puts "Creating employee: #{employee_data["name"]}"

      begin
        # Check if employee already exists by PIN
        existing_employee = nil
        begin
          existing_employee = @services_manager.employee.get_employee_by_pin(emp_data[:pin])
        rescue StandardError => e
          # PIN lookup might not work in all environments
        end

        if existing_employee
          puts "Employee with PIN #{emp_data[:pin]} already exists, skipping creation"
          created_count += 1
          next
        end

        employee = @services_manager.employee.create_employee(employee_data)

        if employee && employee["id"]
          puts "✅ Successfully created employee with ID: #{employee["id"]}"
          created_count += 1
        else
          puts "❌ Error creating employee"
        end
      rescue StandardError => e
        puts "❌ Error creating employee: #{e.message}"
      end
    end

    puts "Created #{created_count} new employees"
  end

  def verify_category_assignments
    puts "\nVerifying category assignments...".colorize(:light_blue)

    # Using the services manager
    inventory_service = @services_manager.inventory

    # Get all categories
    begin
      categories_response = inventory_service.get_categories
      categories = categories_response && categories_response["elements"] ? categories_response["elements"] : []
      puts "Found #{categories.size} categories"
    rescue StandardError => e
      puts "⚠️ Warning: Error getting categories: #{e.message}"
      categories = []
    end

    # Create default categories if none exist
    if categories.empty?
      puts "No categories found. Creating default categories...".colorize(:yellow)
      default_categories = [
        { "name" => "Appetizers" },
        { "name" => "Entrees" },
        { "name" => "Sides" },
        { "name" => "Desserts" },
        { "name" => "Drinks" },
        { "name" => "Alcoholic Beverages" },
        { "name" => "Specials" }
      ]

      created_categories = []
      default_categories.each do |category_data|
        response = inventory_service.create_category(category_data)

        if response && response["id"]
          created_categories << response
          puts "✅ Created category: #{response["name"]} (ID: #{response["id"]})"
        else
          puts "❌ Failed to create category: #{category_data["name"]}"
        end
      rescue StandardError => e
        puts "❌ Error creating category '#{category_data["name"]}': #{e.message}"
      end

      categories = created_categories

      if categories.empty?
        puts "❌ Failed to create any categories. Will use fallback data.".colorize(:red)
        # Create fallback categories (in-memory only)
        categories = default_categories.map.with_index do |cat, i|
          { "id" => "CAT_#{i + 1}", "name" => cat["name"] }
        end
      end
    end

    # Check if any items exist
    begin
      items_response = inventory_service.get_items
      items = items_response && items_response["elements"] ? items_response["elements"] : []
      puts "Found #{items.size} total items"
    rescue StandardError => e
      puts "⚠️ Warning: Error getting items: #{e.message}"
      items = []
    end

    # Check if we need to create sample items
    if items.empty?
      puts "No items found. Creating sample menu items...".colorize(:yellow)

      # Define some sample items for a restaurant
      sample_items = [
        { "name" => "Classic Burger", "price" => 1295, "category" => "Entrees" },
        { "name" => "Caesar Salad", "price" => 995, "category" => "Appetizers" },
        { "name" => "French Fries", "price" => 495, "category" => "Sides" },
        { "name" => "Chocolate Cake", "price" => 795, "category" => "Desserts" },
        { "name" => "Soda", "price" => 295, "category" => "Drinks" },
        { "name" => "Craft Beer", "price" => 695, "category" => "Alcoholic Beverages" },
        { "name" => "Chef's Special", "price" => 1895, "category" => "Specials" }
      ]

      created_items = []

      # Create a category map for easier lookup
      category_map = {}
      categories.each do |category|
        category_map[category["name"]] = category["id"]
      end

      sample_items.each do |item_data|
        category_name = item_data.delete("category")

        begin
          # Create the item
          item_response = inventory_service.create_item(item_data)

          if item_response && item_response["id"]
            created_items << item_response
            puts "✅ Created item: #{item_response["name"]} (ID: #{item_response["id"]})"

            # Assign to category if applicable
            if category_name && category_map[category_name]
              category_id = category_map[category_name]
              begin
                assignment = inventory_service.assign_item_to_category(item_response["id"], category_id)
                if assignment && assignment["id"]
                  puts "  ✓ Assigned to category: #{category_name}"
                else
                  puts "  ✗ Failed to assign to category: #{category_name}"
                end
              rescue StandardError => e
                puts "  ✗ Error assigning to category: #{e.message}"
              end
            end
          else
            puts "❌ Failed to create item: #{item_data["name"]}"
          end
        rescue StandardError => e
          puts "❌ Error creating item '#{item_data["name"]}': #{e.message}"
        end
      end

      items = created_items

      if items.empty?
        puts "❌ Failed to create any items. Using fallback data.".colorize(:red)
        # Create fallback items (in-memory only)
        items = sample_items.map.with_index do |item, i|
          { "id" => "ITEM_#{i + 1}", "name" => item["name"], "price" => item["price"] }
        end
      end
    end

    puts "✅ Category and item verification complete"
  end

  def ensure_other_entities
    puts "\nChecking for other required entities...".colorize(:light_blue)

    # Check for discounts
    begin
      puts "Verifying discounts..."
      discounts = @services_manager.discount.get_discounts
      discount_count = discounts && discounts["elements"] ? discounts["elements"].size : 0

      if discount_count < 3
        puts "Creating standard discounts..."
        @services_manager.discount.create_standard_discounts
        puts "✅ Standard discounts created"
      else
        puts "✅ Found #{discount_count} existing discounts"
      end
    rescue StandardError => e
      puts "⚠️ Warning: Error checking discounts: #{e.message}"
    end

    # Check for tax rates
    begin
      puts "Verifying tax rates..."
      tax_rates = @services_manager.tax.get_tax_rates
      tax_rate_count = tax_rates && tax_rates["elements"] ? tax_rates["elements"].size : 0

      if tax_rate_count < 2
        puts "Creating standard tax rates..."
        @services_manager.tax.create_standard_tax_rates
        puts "✅ Standard tax rates created"
      else
        puts "✅ Found #{tax_rate_count} existing tax rates"
      end
    rescue StandardError => e
      puts "⚠️ Warning: Error checking tax rates: #{e.message}"
    end

    # Check for tables - fallback to creating in-memory tables if API fails
    begin
      puts "Verifying table setup..."
      # Just do a basic check - the TablesService already implements fallbacks
      tables = @services_manager.table.get_tables
      table_count = tables && tables["elements"] ? tables["elements"].size : 0

      if table_count == 0
        puts "Note: No tables found in Clover API. Using fallback tables."
      else
        puts "✅ Found #{table_count} existing tables"
      end
    rescue StandardError => e
      puts "⚠️ Note: Error checking tables: #{e.message}"
      puts "Using fallback tables."
    end

    puts "✅ Entity verification complete"
  end

  def simulate_days
    puts "\nSimulating business days...".colorize(:light_blue)

    (0...options[:days]).each do |day_offset|
      simulation_date = options[:start_date] + day_offset
      puts "Simulating #{simulation_date}..."

      begin
        day_data = restaurant_generator.simulate_business_day(simulation_date)
        puts "  Generated #{day_data[:orders].size} orders, $#{day_data[:total_revenue] / 100.0} revenue"
      rescue StandardError => e
        puts "  ❌ Error simulating day: #{e.message}".colorize(:red)
        puts e.backtrace.join("\n").colorize(:red) if options[:verbose]
      end
    end
  end

  def generate_analytics
    return if restaurant_generator.data[:days].empty?

    puts "\nGenerating analytics...".colorize(:light_blue)
    analytics_generator = CloverRestaurant::DataGeneration::AnalyticsGenerator.new
    @results = { summary: analytics_generator.generate_period_summary(restaurant_generator.data[:days],
                                                                      options[:start_date], options[:days]) }
  rescue StandardError => e
    puts "\nERROR generating analytics: #{e.message}".colorize(:red)
    puts e.backtrace.join("\n").colorize(:red) if options[:verbose]
  end

  def display_results
    puts "\n#{"=" * 80}".colorize(:cyan)
    puts "#{"SIMULATION RESULTS".center(80)}".colorize(:cyan)
    puts "#{"=" * 80}\n".colorize(:cyan)

    summary = results[:summary]
    return puts "No results to display.".colorize(:yellow) if summary.empty?

    # Create a nice formatted table for results
    table = Terminal::Table.new do |t|
      t.title = "#{options[:name]} - Simulation Summary"
      t.add_row ["Total Orders", summary[:total_orders]]
      t.add_row ["Total Revenue", "$#{summary[:total_revenue] / 100.0}"]
      t.add_row ["Total Refunds", "$#{summary[:total_refunds] / 100.0}"] if summary[:total_refunds]
      t.add_row ["Net Revenue", "$#{(summary[:total_revenue] - (summary[:total_refunds] || 0)) / 100.0}"]

      # Add additional metrics if available
      t.add_row ["Average Order Value", "$#{summary[:average_order_value] / 100.0}"] if summary[:average_order_value]

      if summary[:busiest_day]
        t.add_row ["Busiest Day", "#{summary[:busiest_day]} (#{summary[:busiest_day_orders]} orders)"]
      end

      if summary[:top_selling_items] && !summary[:top_selling_items].empty?
        top_item = summary[:top_selling_items].first
        t.add_row ["Top Selling Item", "#{top_item[:name]} (#{top_item[:quantity]} sold)"]
      end
    end

    puts table
  end

  def export_results
    return if results[:summary].empty?

    puts "\nExporting results...".colorize(:light_blue)

    # Create output directory if it doesn't exist
    FileUtils.mkdir_p(options[:export_dir])

    timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
    filename_base = "#{options[:name].downcase.gsub(/\s+/, "_")}_simulation_#{timestamp}"

    case options[:export_format]
    when "json"
      export_json(filename_base)
    when "csv"
      export_csv(filename_base)
    else
      puts "Unsupported export format: #{options[:export_format]}".colorize(:red)
    end
  end

  def export_json(filename_base)
    filename = File.join(options[:export_dir], "#{filename_base}.json")

    File.open(filename, "w") do |file|
      file.write(JSON.pretty_generate(results))
    end

    puts "✅ Results exported to: #{filename}".colorize(:green)
  end

  def export_csv(filename_base)
    # Export summary data
    summary_filename = File.join(options[:export_dir], "#{filename_base}_summary.csv")

    CSV.open(summary_filename, "w") do |csv|
      csv << %w[Metric Value]
      results[:summary].each do |key, value|
        # Format currency values
        csv << if key.to_s.include?("revenue") || key.to_s.include?("value")
                 [key.to_s.gsub("_", " ").capitalize, "$#{value / 100.0}"]
               else
                 [key.to_s.gsub("_", " ").capitalize, value]
               end
      end
    end

    puts "✅ Summary results exported to: #{summary_filename}".colorize(:green)

    # Export daily data if available
    return unless restaurant_generator.data[:days] && !restaurant_generator.data[:days].empty?

    daily_filename = File.join(options[:export_dir], "#{filename_base}_daily.csv")

    CSV.open(daily_filename, "w") do |csv|
      csv << ["Date", "Orders", "Revenue", "Refunds", "Net Revenue"]

      restaurant_generator.data[:days].each do |day|
        csv << [
          day[:date],
          day[:orders].size,
          "$#{day[:total_revenue] / 100.0}",
          "$#{day[:total_refunds] / 100.0}",
          "$#{(day[:total_revenue] - day[:total_refunds]) / 100.0}"
        ]
      end
    end

    puts "✅ Daily results exported to: #{daily_filename}".colorize(:green)
  end
end

# Run the simulator
if __FILE__ == $0
  begin
    RestaurantSimulator.new.run
  rescue StandardError => e
    puts "\nFATAL ERROR: #{e.message}".colorize(:red)
    puts e.backtrace.join("\n").colorize(:red) if ENV["DEBUG"]
    exit 1
  end
end
