#!/usr/bin/env ruby
# simulate_restaurant.rb - Runs a restaurant simulation with configurable parameters
# and generates detailed analytics reports
#
# Usage examples:
#   ruby simulate_restaurant.rb -n "Thai Express" -d 30
#   ruby simulate_restaurant.rb --export --format json
#   ruby simulate_restaurant.rb --start-date 2025-01-01 --verbose

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
require "set" # Required for Set data structure used in analytics

class RestaurantSimulator
  attr_reader :options, :restaurant_generator, :results

  def initialize
    @options = parse_options
    configure_clover
    @restaurant_generator = CloverRestaurant::DataGeneration::RestaurantGenerator.new
    @results = { summary: {} }

    # Make sure the VCR directory exists for caching requests
    FileUtils.mkdir_p("tmp/vcr_cassettes") unless Dir.exist?("tmp/vcr_cassettes")
  end

  def run
    display_header
    setup_restaurant
    run_simulation
    generate_analytics
    display_results
    export_results if options[:export]
  end

  private

  def parse_options
    options = {
      name: ENV["RESTAURANT_NAME"] || "Claude's Bistro",
      days: ENV["SIMULATION_DAYS"]&.to_i || 45,
      start_date: ENV["START_DATE"] ? Date.parse(ENV["START_DATE"]) : Date.today - 45,
      export: ENV["EXPORT_RESULTS"]&.downcase == "true",
      export_format: ENV["EXPORT_FORMAT"]&.downcase || "json",
      export_dir: ENV["EXPORT_DIR"] || "./reports"
    }

    OptionParser.new do |opts|
      opts.banner = "Usage: simulate_restaurant.rb [options]"

      opts.on("-n", "--name NAME", "Restaurant name") do |name|
        options[:name] = name
      end

      opts.on("-d", "--days DAYS", Integer, "Number of days to simulate") do |days|
        options[:days] = days
      end

      opts.on("-s", "--start-date DATE", "Start date (YYYY-MM-DD)") do |date|
        options[:start_date] = Date.parse(date)
      end

      opts.on("-e", "--[no-]export", "Export results to files") do |export|
        options[:export] = export
      end

      opts.on("-f", "--format FORMAT", "Export format (json, csv)") do |format|
        options[:export_format] = format.downcase
      end

      opts.on("-o", "--output-dir DIR", "Directory for exported files") do |dir|
        options[:export_dir] = dir
      end

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
  end

  def display_header
    puts "\n#{"=" * 80}".colorize(:cyan)
    puts "#{"RESTAURANT SIMULATION".center(80)}".colorize(:cyan)
    puts "#{"=" * 80}\n".colorize(:cyan)

    puts "Simulating #{options[:days]} days of operation for: #{options[:name]}".colorize(:yellow)
    puts "Starting from: #{options[:start_date]}"
    puts "Merchant ID: #{ENV["CLOVER_MERCHANT_ID"]}"
    puts "Environment: #{ENV["CLOVER_ENVIRONMENT"] || "https://sandbox.dev.clover.com/"}"
    puts "Exporting results: #{options[:export] ? "Yes (#{options[:export_format].upcase})" : "No"}"
  end

  def setup_restaurant
    puts "\nSetting up restaurant...".colorize(:light_blue)

    begin
      restaurant_generator.setup_restaurant(options[:name])

      # Print summary of setup
      puts "\nRestaurant setup complete!".colorize(:green)

      data = restaurant_generator.data
      setup_table = Terminal::Table.new do |t|
        t.title = "Restaurant Configuration"
        t.style = { border_x: "-", border_i: "+", border_y: "|" }
        t.add_row ["Categories", data[:inventory][:categories].size]
        t.add_row ["Items", data[:inventory][:items].size]
        t.add_row ["Modifier Groups", data[:modifier_groups].size]
        t.add_row ["Tax Rates", data[:tax_rates].size]
        t.add_row ["Discounts", data[:discounts].size]
        t.add_row ["Employees", data[:employees].size]
        t.add_row ["Tables", data[:tables].size]
        t.add_row ["Customers", data[:customers].size]
      end

      puts setup_table
    rescue StandardError => e
      puts "\nERROR during restaurant setup: #{e.message}".colorize(:red)
      puts e.backtrace.join("\n").colorize(:red) if options[:verbose]
      exit 1
    end
  end

  def run_simulation
    puts "\nStarting #{options[:days]}-day simulation...".colorize(:light_blue)
    puts "This may take some time. Progress will be shown as each day completes."

    progress_bar_width = 50
    simulation_errors = []

    options[:days].times do |day_index|
      current_date = options[:start_date] + day_index

      # Print progress
      percent_complete = ((day_index + 1).to_f / options[:days] * 100).round
      completed_chars = (percent_complete * progress_bar_width / 100).round
      remaining_chars = progress_bar_width - completed_chars

      print "\r[#{"█" * completed_chars}#{" " * remaining_chars}] #{percent_complete}% - Simulating #{current_date}"

      # Simulate the day
      begin
        restaurant_generator.simulate_business_day(current_date)
      rescue StandardError => e
        simulation_errors << { date: current_date, error: e.message }
        puts "\nWarning: Error on #{current_date}: #{e.message}".colorize(:yellow)
      end
    end

    puts "\n"

    # Report any errors that occurred during simulation
    return unless simulation_errors.any?

    puts "\nSimulation completed with #{simulation_errors.size} errors:".colorize(:yellow)
    simulation_errors.each do |error|
      puts "- #{error[:date]}: #{error[:error]}".colorize(:yellow)
    end
  end

  def generate_analytics
    return if restaurant_generator.data[:days].empty?

    begin
      analytics_generator = CloverRestaurant::DataGeneration::AnalyticsGenerator.new

      @results = {
        summary: analytics_generator.generate_period_summary(
          restaurant_generator.data[:days],
          options[:start_date],
          options[:days]
        )
      }

      # Generate additional reports if available in the AnalyticsGenerator
      if analytics_generator.respond_to?(:generate_sales_report)
        puts "Generating detailed sales report...".colorize(:light_blue) if options[:verbose]
        @results[:sales_report] = analytics_generator.generate_sales_report(
          restaurant_generator.data[:days],
          options[:start_date],
          options[:start_date] + options[:days] - 1
        )
      end

      if analytics_generator.respond_to?(:generate_item_sales_report)
        puts "Generating item sales report...".colorize(:light_blue) if options[:verbose]
        @results[:item_sales] = analytics_generator.generate_item_sales_report(
          restaurant_generator.data[:days],
          options[:start_date],
          options[:start_date] + options[:days] - 1
        )
      end

      # Add a function to generate employee performance report if not already present
      unless analytics_generator.respond_to?(:generate_employee_report)
        @results[:employee_report] = generate_employee_performance_report(
          restaurant_generator.data[:days],
          options[:start_date],
          options[:start_date] + options[:days] - 1
        )
      end
    rescue StandardError => e
      puts "\nERROR generating analytics: #{e.message}".colorize(:red)
      puts e.backtrace.join("\n").colorize(:red) if options[:verbose]
    end
  end

  # Custom method to generate employee performance report
  def generate_employee_performance_report(days_data, start_date, end_date)
    puts "Generating employee performance report...".colorize(:light_blue) if options[:verbose]

    # Filter data to date range
    filtered_days = days_data.select { |day| day[:date] >= start_date && day[:date] <= end_date }

    # Initialize report
    report = {
      period: {
        start_date: start_date,
        end_date: end_date,
        days: (end_date - start_date + 1).to_i
      },
      employees: {},
      top_performers: [],
      daily_breakdown: {}
    }

    # Process each day
    filtered_days.each do |day|
      next unless day[:date]

      # Track employee performance
      day[:employee_orders].each do |employee_name, order_count|
        report[:employees][employee_name] ||= {
          total_orders: 0,
          total_revenue: 0,
          avg_revenue_per_order: 0,
          days_worked: 0
        }

        report[:employees][employee_name][:total_orders] += order_count
        report[:employees][employee_name][:days_worked] += 1

        # Track daily breakdown
        date_key = day[:date].to_s
        report[:daily_breakdown][date_key] ||= {}
        report[:daily_breakdown][date_key][employee_name] = order_count
      end
    end

    # Calculate additional metrics and sort employees by performance
    report[:employees].each do |name, data|
      # Calculate average metrics
      data[:avg_orders_per_day] = (data[:total_orders].to_f / data[:days_worked]).round(2) if data[:total_orders] > 0
    end

    # Get top performers by total orders
    report[:top_performers] = report[:employees].sort_by { |_, data| -data[:total_orders] }.first(5)

    report
  end

  def display_results
    puts "\n#{"=" * 80}".colorize(:cyan)
    puts "#{"SIMULATION RESULTS".center(80)}".colorize(:cyan)
    puts "#{"=" * 80}\n".colorize(:cyan)

    summary = results[:summary]
    return puts "No results to display.".colorize(:yellow) if summary.empty?

    # Business Overview
    puts "BUSINESS OVERVIEW:".colorize(:light_blue)
    overview_table = Terminal::Table.new do |t|
      t.title = "Business Summary"
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
      t.title = "Best Sellers"
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
      t.title = "Employee Performance"
      t.headings = ["Employee", "Orders Processed"]
      t.style = { border_x: "-", border_i: "+", border_y: "|" }

      summary[:employee_order_counts].first(10).each do |employee_name, order_count|
        t.add_row [employee_name, order_count]
      end
    end
    puts top_employees_table

    # Display employee performance report if available
    if results[:employee_report] && !results[:employee_report][:top_performers].empty?
      puts "\nDETAILED EMPLOYEE METRICS:".colorize(:light_blue)
      employee_metrics_table = Terminal::Table.new do |t|
        t.title = "Employee Detailed Metrics"
        t.headings = ["Employee", "Orders", "Days Worked", "Avg Orders/Day"]
        t.style = { border_x: "-", border_i: "+", border_y: "|" }

        results[:employee_report][:top_performers].each do |name, data|
          t.add_row [
            name,
            data[:total_orders],
            data[:days_worked],
            data[:avg_orders_per_day]
          ]
        end
      end
      puts employee_metrics_table
    end

    # Daily Revenue Chart (simple text-based chart)
    puts "\nDAILY REVENUE CHART:".colorize(:light_blue)
    daily_revenue = summary[:daily_revenue]

    # Find max revenue for scaling
    max_revenue = daily_revenue.map { |day| day[:revenue] }.max.to_f
    chart_width = 50

    # Print chart header
    puts "Date         " + "Revenue".rjust(chart_width + 11)
    puts "------------" + "-" * (chart_width + 11)

    daily_revenue.each do |day|
      date_str = day[:date].to_s
      revenue = day[:revenue]
      net_revenue = day[:net_revenue] || revenue

      # Skip days with no revenue (helps with visual clarity)
      next if revenue == 0

      bar_length = (revenue / max_revenue * chart_width).round

      # Format the output
      date_part = date_str.ljust(12)
      bar_part = "█" * bar_length
      revenue_part = currency_format(revenue).rjust(10)

      # Add a different color for weekend days and special color for highest revenue day
      line_color = if day[:date].to_s == summary[:busiest_day]
                     :light_green # Highlight busiest day
                   elsif day[:date].saturday? || day[:date].sunday?
                     :light_yellow # Weekend
                   else
                     :white        # Weekday
                   end

      puts "#{date_part} #{bar_part} #{revenue_part}".colorize(line_color)
    end

    puts "\nSimulation completed successfully!".colorize(:green)
    puts "All data has been uploaded to your Clover merchant account."
    puts "You can now log in to the Clover Dashboard to view the results."

    return unless options[:export]

    puts "\nResults exported to: #{options[:export_dir]}".colorize(:green)
  end

  def export_results
    return if results[:summary].empty?

    # Create export directory if it doesn't exist
    FileUtils.mkdir_p(options[:export_dir])

    timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
    base_filename = "#{options[:name].downcase.gsub(/\s+/, "_")}_simulation_#{timestamp}"

    case options[:export_format]
    when "json"
      export_json(base_filename)
    when "csv"
      export_csv(base_filename)
    else
      puts "Unsupported export format: #{options[:export_format]}".colorize(:yellow)
    end
  end

  def export_json(base_filename)
    # Export summary
    File.open(File.join(options[:export_dir], "#{base_filename}_summary.json"), "w") do |f|
      # Convert any Set objects to arrays for JSON serialization
      cleaned_summary = deep_clean_for_json(results[:summary])
      f.write(JSON.pretty_generate(cleaned_summary))
    end

    # Export sales report if available
    if results[:sales_report]
      File.open(File.join(options[:export_dir], "#{base_filename}_sales_report.json"), "w") do |f|
        cleaned_report = deep_clean_for_json(results[:sales_report])
        f.write(JSON.pretty_generate(cleaned_report))
      end
    end

    # Export item sales if available
    return unless results[:item_sales]

    File.open(File.join(options[:export_dir], "#{base_filename}_item_sales.json"), "w") do |f|
      cleaned_item_sales = deep_clean_for_json(results[:item_sales])
      f.write(JSON.pretty_generate(cleaned_item_sales))
    end
  end

  # Helper method to prepare data for JSON by converting any Set objects to arrays
  def deep_clean_for_json(obj)
    case obj
    when Set
      obj.to_a
    when Hash
      result = {}
      obj.each do |k, v|
        result[k] = deep_clean_for_json(v)
      end
      result
    when Array
      obj.map { |item| deep_clean_for_json(item) }
    else
      obj
    end
  end

  def export_csv(base_filename)
    # Export summary daily revenue
    CSV.open(File.join(options[:export_dir], "#{base_filename}_daily_revenue.csv"), "w") do |csv|
      csv << ["Date", "Revenue", "Net Revenue"]

      results[:summary][:daily_revenue].each do |day|
        csv << [day[:date], day[:revenue], day[:net_revenue]]
      end
    end

    # Export top selling items
    CSV.open(File.join(options[:export_dir], "#{base_filename}_top_items.csv"), "w") do |csv|
      csv << ["Item", "Quantity Sold"]

      results[:summary][:top_selling_items].each do |item_name, quantity|
        csv << [item_name, quantity]
      end
    end

    # Export employee performance
    CSV.open(File.join(options[:export_dir], "#{base_filename}_employees.csv"), "w") do |csv|
      csv << ["Employee", "Orders Processed"]

      results[:summary][:employee_order_counts].each do |employee_name, order_count|
        csv << [employee_name, order_count]
      end
    end
  end

  def currency_format(amount_cents)
    return "$0.00" if amount_cents.nil? || amount_cents == 0

    "$#{format("%.2f", amount_cents / 100.0)}"
  end
end

# Run the simulator if this file is executed directly
if __FILE__ == $0
  begin
    RestaurantSimulator.new.run
  rescue StandardError => e
    puts "\nFATAL ERROR: #{e.message}".colorize(:red)
    puts e.backtrace.join("\n").colorize(:red) if ENV["DEBUG"]
    exit 1
  end
end
