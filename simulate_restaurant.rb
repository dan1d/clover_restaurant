#!/usr/bin/env ruby
# simulate_restaurant.rb - Runs a full 45-day restaurant simulation

# Add the local lib directory to the load path
$LOAD_PATH.unshift(File.expand_path("lib", __dir__))

require "clover_restaurant"
require "dotenv/load" # Load environment variables from .env file
require "date"
require "terminal-table"
require "colorize"
require "active_support/time"

# Configure the gem with credentials from environment variables
CloverRestaurant.configure do |config|
  config.merchant_id = ENV["CLOVER_MERCHANT_ID"] || raise("Please set CLOVER_MERCHANT_ID in .env file")

  if ENV["CLOVER_API_KEY"]
    config.api_key = ENV["CLOVER_API_KEY"]
  elsif ENV["CLOVER_API_TOKEN"]
    config.api_token = ENV["CLOVER_API_TOKEN"]
  else
    raise "Please set either CLOVER_API_KEY or CLOVER_API_TOKEN in .env file"
  end

  config.environment = ENV["CLOVER_ENVIRONMENT"] || "https://sandbox.dev.clover.com/"
  config.log_level = ENV["LOG_LEVEL"] ? Logger.const_get(ENV["LOG_LEVEL"]) : Logger::INFO
end

def currency_format(amount_cents)
  "$#{format("%.2f", amount_cents / 100.0)}"
end

begin
  puts "\n#{"=" * 80}".colorize(:cyan)
  puts "#{" " * 30}RESTAURANT SIMULATION".colorize(:cyan)
  puts "#{"=" * 80}\n".colorize(:cyan)

  restaurant_name = ENV["RESTAURANT_NAME"] || "Claude's Bistro"
  simulation_days = ENV["SIMULATION_DAYS"]&.to_i || 45
  start_date = ENV["START_DATE"] ? Date.parse(ENV["START_DATE"]) : Date.today - simulation_days

  puts "Simulating #{simulation_days} days of operation for: #{restaurant_name}".colorize(:yellow)
  puts "Starting from: #{start_date}"
  puts "Merchant ID: #{ENV["CLOVER_MERCHANT_ID"]}"
  puts "Environment: #{ENV["CLOVER_ENVIRONMENT"] || "https://sandbox.dev.clover.com/"}"

  # Create the restaurant generator
  restaurant_generator = CloverRestaurant::DataGeneration::RestaurantGenerator.new

  # Setup the restaurant
  puts "\nSetting up restaurant...".colorize(:light_blue)
  restaurant_generator.setup_restaurant(restaurant_name)

  # Print summary of setup
  puts "\nRestaurant setup complete!".colorize(:green)
  puts "Categories: #{restaurant_generator.data[:inventory][:categories].size}"
  puts "Items: #{restaurant_generator.data[:inventory][:items].size}"
  puts "Modifier Groups: #{restaurant_generator.data[:modifier_groups].size}"
  puts "Tax Rates: #{restaurant_generator.data[:tax_rates].size}"
  puts "Discounts: #{restaurant_generator.data[:discounts].size}"
  puts "Employees: #{restaurant_generator.data[:employees].size}"
  puts "Tables: #{restaurant_generator.data[:tables].size}"
  puts "Customers: #{restaurant_generator.data[:customers].size}"

  # Run simulation for specified number of days
  puts "\nStarting #{simulation_days}-day simulation...".colorize(:light_blue)
  puts "This may take some time. Progress will be shown as each day completes."

  progress_bar_width = 50
  simulation_days.times do |day_index|
    current_date = start_date + day_index

    # Print progress
    percent_complete = ((day_index + 1).to_f / simulation_days * 100).round
    completed_chars = (percent_complete * progress_bar_width / 100).round
    remaining_chars = progress_bar_width - completed_chars

    print "\r[#{"█" * completed_chars}#{" " * remaining_chars}] #{percent_complete}% - Simulating #{current_date}"

    # Simulate the day
    restaurant_generator.simulate_business_day(current_date)
  end

  # Generate summary for the entire period
  results = {
    summary: if restaurant_generator.data[:days].last[:date]
               CloverRestaurant::DataGeneration::AnalyticsGenerator.new.generate_period_summary(
                 restaurant_generator.data[:days], start_date, simulation_days
               )
             else
               {}
             end
  }

  puts "\n\n#{"=" * 80}".colorize(:cyan)
  puts "#{"SIMULATION RESULTS".center(80)}".colorize(:cyan)
  puts "#{"=" * 80}\n".colorize(:cyan)

  summary = results[:summary]

  # Business Overview
  puts "BUSINESS OVERVIEW:".colorize(:light_blue)
  overview_table = Terminal::Table.new do |t|
    t.style = { border_x: "-", border_i: "+", border_y: "|" }
    t.add_row ["Period", "#{summary[:period_start]} to #{summary[:period_end]} (#{summary[:total_days]} days)"]
    t.add_row ["Total Orders", summary[:total_orders]]
    t.add_row ["Total Revenue", currency_format(summary[:total_revenue])]
    t.add_row ["Total Refunds", currency_format(summary[:total_refunds])]
    t.add_row ["Net Revenue", currency_format(summary[:total_net_revenue])]
    t.add_row ["Average Order Value", currency_format(summary[:average_order_value])]
    t.add_row ["Total Customers Served", summary[:total_customers_served]]
    t.add_row ["Total Items Sold", summary[:total_items_sold]]
    t.add_row ["Busiest Day", "#{summary[:busiest_day]} (#{summary[:busiest_day_orders]} orders)"]
  end
  puts overview_table

  # Top Selling Items
  puts "\nTOP SELLING ITEMS:".colorize(:light_blue)
  top_items_table = Terminal::Table.new do |t|
    t.headings = ["Item", "Quantity Sold"]
    t.style = { border_x: "-", border_i: "+", border_y: "|" }

    summary[:top_selling_items].each do |item_name, quantity|
      t.add_row [item_name, quantity]
    end
  end
  puts top_items_table

  # Top Employees
  puts "\nTOP EMPLOYEES BY ORDERS:".colorize(:light_blue)
  top_employees_table = Terminal::Table.new do |t|
    t.headings = ["Employee", "Orders Processed"]
    t.style = { border_x: "-", border_i: "+", border_y: "|" }

    summary[:employee_order_counts].first(10).each do |employee_name, order_count|
      t.add_row [employee_name, order_count]
    end
  end
  puts top_employees_table

  # Daily Revenue Chart (simple text-based chart)
  puts "\nDAILY REVENUE CHART:".colorize(:light_blue)
  daily_revenue = summary[:daily_revenue]

  # Find max revenue for scaling
  max_revenue = daily_revenue.map { |day| day[:revenue] }.max.to_f
  chart_width = 50

  daily_revenue.each do |day|
    date_str = day[:date].to_s
    revenue = day[:revenue]
    net_revenue = day[:net_revenue]

    # Skip days with no revenue (helps with visual clarity)
    next if revenue == 0

    bar_length = (revenue / max_revenue * chart_width).round

    # Format the output
    date_part = date_str.ljust(12)
    bar_part = "█" * bar_length
    revenue_part = currency_format(revenue).rjust(10)

    puts "#{date_part} #{bar_part} #{revenue_part}"
  end

  puts "\nSimulation completed successfully!".colorize(:green)
  puts "All data has been uploaded to your Clover merchant account."
  puts "You can now log in to the Clover Dashboard to view the results."
rescue StandardError => e
  puts "\nERROR: #{e.message}".colorize(:red)
  puts e.backtrace.join("\n").colorize(:red) if ENV["DEBUG"]
  exit 1
end
