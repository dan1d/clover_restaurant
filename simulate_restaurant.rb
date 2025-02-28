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
  attr_reader :options, :restaurant_generator, :results

  def initialize
    @options = parse_options
    configure_clover
    @restaurant_generator = CloverRestaurant::DataGeneration::RestaurantGenerator.new
    @results = { summary: {} }
  end

  def run
    display_header
    setup_restaurant
    create_orders_and_payments
    generate_analytics
    display_results
    export_results if options[:export]
  end

  private

  def parse_options
    options = {
      name: ENV["RESTAURANT_NAME"] || "Claude's Bistro",
      days: 10, # Simulate last 10 days
      start_date: Date.today - 10, # Start from 10 days ago
      export: ENV["EXPORT_RESULTS"]&.downcase == "true",
      export_format: ENV["EXPORT_FORMAT"]&.downcase || "json",
      export_dir: ENV["EXPORT_DIR"] || "./reports"
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
  end

  def setup_restaurant
    puts "\nSetting up restaurant...".colorize(:light_blue)
    restaurant_generator.setup_restaurant(options[:name])
  rescue StandardError => e
    puts "\nERROR during restaurant setup: #{e.message}".colorize(:red)
    puts e.backtrace.join("\n").colorize(:red) if options[:verbose]
    exit 1
  end

  def create_orders_and_payments
    puts "\nCreating sample orders and payments for the last #{options[:days]} days...".colorize(:light_blue)

    order_service = CloverRestaurant::Services::OrderService.new
    employee_service = CloverRestaurant::Services::EmployeeService.new
    payment_service = CloverRestaurant::Services::PaymentService.new

    employees = employee_service.get_employees
    employee_id = employees["elements"]&.first&.dig("id")

    if employee_id.nil?
      puts "❌ No employees found. Cannot create orders."
      return
    end

    puts "✅ Using Employee ID: #{employee_id}"

    # Loop through the past 10 days and create orders
    (0...options[:days]).each do |day_offset|
      order_date = options[:start_date] + day_offset

      puts "\n📅 Creating orders for #{order_date}..."

      order_data = {
        "employee" => { "id" => employee_id },
        "diningOption" => "HERE",
        "createdTime" => (order_date.to_time.to_i * 1000) # Convert to milliseconds for Clover API
      }

      order = order_service.create_order(order_data)

      if order && order["id"]
        order_id = order["id"]
        puts "✅ Created Order for #{order_date}: #{order_id}"

        # Mark the order as paid
        order_service.update_order(order_id, { "paymentState" => "PAID" })

        # Encrypt card details
        card_details = {
          card_number: "4111111111111111", # Test Visa Card
          exp_month: 12,
          exp_year: 2025,
          cvv: 123
        }

        # Process payment
        response = payment_service.create_payment(order_id, 500, card_details) # $5.00

        if response && response["status"] == "APPROVED"
          puts "✅ Payment successful for Order #{order_id}, Payment ID: #{response["id"]}"
          payment_service.update_order_total(order_id, 500)
        else
          puts "❌ Payment failed for Order #{order_id}"
        end
      else
        puts "❌ Failed to create order for #{order_date}"
      end
    end
  end

  def generate_analytics
    return if restaurant_generator.data[:days].empty?

    analytics_generator = CloverRestaurant::DataGeneration::AnalyticsGenerator.new
    @results = { summary: analytics_generator.generate_period_summary(restaurant_generator.data[:days],
                                                                      options[:start_date], options[:days]) }
  rescue StandardError => e
    puts "\nERROR generating analytics: #{e.message}".colorize(:red)
  end

  def display_results
    puts "\n#{"=" * 80}".colorize(:cyan)
    puts "#{"SIMULATION RESULTS".center(80)}".colorize(:cyan)
    puts "#{"=" * 80}\n".colorize(:cyan)

    summary = results[:summary]
    return puts "No results to display.".colorize(:yellow) if summary.empty?

    puts "Total Orders: #{summary[:total_orders]}"
    puts "Total Revenue: $#{summary[:total_revenue] / 100.0}"
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
