#!/usr/bin/env ruby
# restaurant_simulator.rb - Main entry point for the Clover automation gem

$LOAD_PATH.unshift(File.expand_path("lib", __dir__))

require "clover_restaurant"
begin
  require "dotenv/load"
rescue LoadError
  puts "dotenv gem not found, skipping .env file loading"
end

require "date"
require "terminal-table"
require "colorize"
require "active_support/time"
require "json"
require "csv"
require "fileutils"
require "set"
require "net/http"
require "logger"

class CloverAutomation
  # Configuration constants
  API_VERSION = "v3"
  DEFAULT_ORDERS_PER_DAY = 2..4
  DEFAULT_DAYS_RANGE = 30

  attr_reader :services_manager, :entity_generator, :logger

  def initialize
    configure_clover
    setup_services
    configure_logger
  end

  def run
    display_header
    setup_entities
    generate_past_orders
  end

  def delete_everything
    puts "\n🚨 Deleting all Clover entities...".colorize(:light_blue)
    @entity_generator.delete_all_entities
    puts "✅ All Clover entities deleted successfully."
  end

  private

  #
  # Setup and Configuration Methods
  #

  def configure_clover
    CloverRestaurant.configure do |config|
      config.merchant_id = ENV["CLOVER_MERCHANT_ID"] || raise("Please set CLOVER_MERCHANT_ID in .env file")
      config.api_token = ENV["CLOVER_API_TOKEN"] || raise("Please set CLOVER_API_TOKEN in .env file")
      config.environment = ENV["CLOVER_ENVIRONMENT"] || "https://sandbox.dev.clover.com/"
      config.log_level = ENV["LOG_LEVEL"] ? Logger.const_get(ENV["LOG_LEVEL"]) : Logger::INFO
    end
  end

  def setup_services
    @services_manager = CloverRestaurant::CloverServicesManager.new
    @entity_generator = CloverRestaurant::DataGeneration::EntityGenerator.new(
      @services_manager.config, @services_manager
    )
    @api_token = @services_manager.config.api_token
    @merchant_id = @services_manager.config.merchant_id
    @environment = @services_manager.config.environment.chomp("/")
  end

  def configure_logger
    @logger = Logger.new($stdout)
    @logger.level = Logger::INFO
    @logger.formatter = proc do |severity, datetime, progname, msg|
      formatted_datetime = datetime.strftime("%Y-%m-%d %H:%M:%S")
      color = case severity
              when "INFO" then :light_blue
              when "WARN" then :yellow
              when "ERROR" then :red
              else :white
              end
      "#{formatted_datetime} [#{severity}] #{msg.to_s.colorize(color)}\n"
    end
  end

  def display_header
    puts "\n#{"=" * 80}".colorize(:cyan)
    puts "#{"CLOVER AUTOMATION".center(80)}".colorize(:cyan)
    puts "#{"=" * 80}\n".colorize(:cyan)

    puts "Merchant ID: #{@merchant_id}"
    puts "Environment: #{@environment}"
  end

  def setup_entities
    logger.info "Setting up Clover entities..."
    @entity_generator.create_entities
    @services_manager.tender.create_standard_tenders
    logger.info "Clover setup complete"
  end

  #
  # Order Generation Methods
  #

  def generate_past_orders(days_range = DEFAULT_DAYS_RANGE, orders_per_day_range = DEFAULT_ORDERS_PER_DAY)
    logger.info "Generating multiple orders per day for the past #{days_range} days..."

    # Load all required data upfront to minimize API calls
    resources = load_all_resources
    validate_resources(resources)

    successful_orders = []

    # Create orders for each day in the range
    (15..days_range).each do |days_ago|
      past_date = Time.now - days_ago.days
      date_string = past_date.strftime("%Y-%m-%d")

      # Random number of orders per day
      num_orders = rand(orders_per_day_range)
      logger.info "Creating #{num_orders} orders for #{date_string}..."

      # Create orders for this date in batch
      new_orders = process_batch_orders_for_date(
        past_date,
        num_orders,
        resources
      )

      successful_orders.concat(new_orders)
    end

    # Print summary table
    print_order_summary(successful_orders)
  end

  def load_all_resources
    logger.info "Loading resources from Clover..."

    resources = {
      items: fetch_with_rescue { @services_manager.inventory.get_items["elements"] },
      categories: fetch_with_rescue { @services_manager.inventory.get_categories["elements"] },
      customers: fetch_with_rescue { @services_manager.customer.get_customers["elements"] },
      employees: fetch_with_rescue { @services_manager.employee.get_employees["elements"] },
      tenders: filter_safe_tenders(fetch_with_rescue { @services_manager.tender.get_tenders }),
      discounts: fetch_with_rescue { @services_manager.discount.get_discounts["elements"] }
    }

    # Pre-organize items by category to avoid duplicate processing
    resources[:category_map] = organize_items_by_category(resources[:categories], resources[:items])

    logger.info "Resources loaded successfully"
    resources
  end

  def filter_safe_tenders(tenders)
    # Filter out credit/debit card tenders that won't work in sandbox
    safe_tenders = tenders.reject do |tender|
      tender["label"] == "Credit Card" ||
        tender["label"] == "Debit Card" ||
        (tender["labelKey"] && (tender["labelKey"].include?("credit") || tender["labelKey"].include?("debit")))
    end

    # Create safe tenders if none exist
    if safe_tenders.empty?
      logger.warn "No external tenders found. Creating custom tenders..."
      safe_tenders = create_safe_tenders
    end

    safe_tenders
  end

  def create_safe_tenders
    tender_types = [
      { label: "External Payment", key: "com.clover.tender.external" },
      { label: "Cash", key: "com.clover.tender.cash" },
      { label: "Gift Card", key: "com.clover.tender.gift_card" },
      { label: "Check", key: "com.clover.tender.check" }
    ]

    safe_tenders = []
    tender_types.each do |tender_type|
      tender = @services_manager.tender.create_tender({
                                                        "label" => tender_type[:label],
                                                        "labelKey" => tender_type[:key],
                                                        "enabled" => true,
                                                        "visible" => true,
                                                        "opensCashDrawer" => %w[Cash
                                                                                Check].include?(tender_type[:label])
                                                      })
      safe_tenders << tender if tender
    end

    safe_tenders
  end

  def organize_items_by_category(categories, items)
    category_map = {}

    # Add items to their categories
    items.each do |item|
      next unless item["categories"] && item["categories"]["elements"]

      item["categories"]["elements"].each do |category|
        category_id = category["id"]
        category_map[category_id] ||= []
        category_map[category_id] << item
      end
    end

    # For items without categories, create a "Miscellaneous" category
    uncategorized = items.select { |item| !item["categories"] || item["categories"]["elements"].empty? }
    category_map["misc"] = uncategorized unless uncategorized.empty?

    category_map
  end

  def process_batch_orders_for_date(date, num_orders, resources)
    successful_orders = []

    num_orders.times do |order_index|
      # Create time for this order - distribute throughout the day
      timestamp = generate_timestamp_for_order(date, order_index, num_orders)
      time_str = Time.at(timestamp / 1000).strftime("%Y-%m-%d %H:%M")
      puts ">>>>>>>>>>>>>>> #{time_str} ------ #{timestamp}"

      # Select random resources for this order
      order_resources = {
        employee: resources[:employees].sample,
        customer: resources[:customers].sample,
        tender: resources[:tenders].sample,
        dining_option: %w[HERE TO_GO DELIVERY].sample
      }

      # Generate line items and calculate discount
      line_items_data = generate_line_items(resources[:category_map], resources[:items])
      total_price = calculate_total_price(line_items_data)

      # Apply discount if needed
      discount_data = nil
      if rand < 0.3 && !resources[:discounts].empty?
        discount = resources[:discounts].sample
        discount_amount = calculate_discount_amount(discount, total_price)
        if discount_amount > 0
          discount_data = discount
          total_price -= discount_amount
          logger.info "Applied #{discount["name"]} discount (-$#{discount_amount / 100.0})"
        end
      end

      logger.info "Creating order for #{time_str} with #{line_items_data.length} items, total: $#{total_price / 100.0}"

      # Create complete order with minimal API calls
      order_result = create_optimized_order(
        timestamp,
        order_resources,
        line_items_data,
        discount_data,
        total_price
      )

      next unless order_result

      order_time = Time.at(timestamp / 1000).strftime("%H:%M")
      successful_orders << {
        id: order_result[:order_id],
        date: date.strftime("%Y-%m-%d"),
        time: order_time,
        total: order_result[:total],
        employee: order_resources[:employee]["displayName"] || order_resources[:employee]["name"] || order_resources[:employee]["id"],
        tender: order_resources[:tender]["label"]
      }

      logger.info "Order #{order_result[:order_id]} completed for #{date.strftime("%Y-%m-%d")} at #{order_time} - $#{order_result[:total] / 100.0}"
    end

    successful_orders
  end

  def generate_timestamp_for_order(date, order_index, total_orders)
    # Distribute orders throughout business hours
    hour = 7 + ((order_index.to_f / total_orders) * 15).round # 7am to 10pm
    minute = rand(0..59)
    second = rand(0..59)

    time = Time.new(date.year, date.month, date.day, hour, minute, second)
    (time.to_i * 1000).to_i # Convert to milliseconds
  end

  def generate_line_items(category_map, all_items)
    line_items = []
    categories_to_use = category_map.keys.sample(rand(1..3))

    categories_to_use.each do |category_id|
      # Get items from this category, or fall back to all items
      category_items = category_map[category_id] || all_items
      next if category_items.empty?

      # Select 1-3 items from this category
      items_to_add = category_items.sample(rand(1..3))

      items_to_add.each do |item|
        quantity = rand(1..2)
        item_price = item["price"] || 0

        line_items << {
          item: item,
          quantity: quantity,
          price: item_price
        }
      end
    end

    line_items
  end

  def calculate_total_price(line_items)
    line_items.sum { |item| item[:price] * item[:quantity] }
  end

  def calculate_discount_amount(discount, total_price)
    if discount["percentage"]
      (total_price * discount["percentage"].to_f / 100).round
    elsif discount["amount"]
      [discount["amount"], total_price].min
    else
      0
    end
  end

  # Optimized order creation that minimizes API calls
  def create_optimized_order(timestamp, resources, line_items, discount, total_price)
    # Step 1: Create the basic order shell - must be done first to get an order ID
    order_data = {
      "employee" => { "id" => resources[:employee]["id"] },
      "customers" => [{ "id" => resources[:customer]["id"] }],
      "diningOption" => resources[:dining_option],
      "createdTime" => timestamp,
      "clientCreatedTime" => timestamp,
      "modifiedTime" => timestamp,
      "clientModifiedTime" => timestamp,
      "state" => "OPEN" # Pre-set to OPEN state
    }

    order_response = make_api_request("POST", "orders", order_data)

    return nil unless order_response && order_response["id"]

    order_id = order_response["id"]

    # Step 2: Add line items - unfortunately this must be separate calls
    line_items.each do |line_item|
      line_item_data = {
        "item" => { "id" => line_item[:item]["id"] },
        "quantity" => line_item[:quantity]
      }

      line_item_response = make_api_request("POST", "orders/#{order_id}/line_items", line_item_data)

      if line_item_response
        logger.info "Added #{line_item[:item]["name"] || line_item[:item]["id"]} - $#{line_item[:price] / 100.0} x #{line_item[:quantity]}"
      end
    end

    # Step 3: Update order with correct timestamps, total, and state
    update_data = {
      "createdTime" => timestamp,
      "clientCreatedTime" => timestamp,
      "total" => total_price
    }

    make_api_request("POST", "orders/#{order_id}", update_data)

    # Step 4: Process payment
    payment_result = process_payment(
      order_id,
      resources[:employee]["id"],
      resources[:tender]["id"],
      total_price,
      timestamp
    )

    # Return result or nil if payment failed
    payment_result ? { order_id: order_id, total: total_price } : nil
  end

  def process_payment(order_id, employee_id, tender_id, amount, timestamp)
    return false if amount <= 0

    logger.info "Processing payment: $#{amount / 100.0}..."

    payment_data = {
      "tender" => { "id" => tender_id },
      "employee" => { "id" => employee_id },
      "amount" => amount,
      "createdTime" => timestamp,
      "clientCreatedTime" => timestamp
    }

    response = make_api_request("POST", "orders/#{order_id}/payments", payment_data)

    if response && response["id"]
      logger.info "Payment processed successfully"

      # One final timestamp update to ensure consistency
      make_api_request("POST", "orders/#{order_id}", {
                         "createdTime" => timestamp,
                         "clientCreatedTime" => timestamp,
                         "modifiedTime" => timestamp
                       })

      true
    else
      logger.error "Payment failed"
      false
    end
  end

  #
  # Utility Methods
  #

  def fetch_with_rescue
    yield
  rescue StandardError => e
    logger.error "Error fetching data: #{e.message}"
    []
  end

  def validate_resources(resources)
    errors = []
    errors << "No items available" if resources[:items].empty?
    errors << "No employees available" if resources[:employees].empty?
    errors << "No customers available" if resources[:customers].empty?
    errors << "No payment tenders available" if resources[:tenders].empty?

    return unless errors.any?

    logger.error "Cannot create orders: #{errors.join(", ")}"
    exit 1
  end

  def make_api_request(method, endpoint, data = nil)
    uri = URI.parse("#{@environment}/#{API_VERSION}/merchants/#{@merchant_id}/#{endpoint}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    puts "DATA: #{data}" if data
    headers = {
      "Authorization" => "Bearer #{@api_token}",
      "Content-Type" => "application/json"
    }

    request = case method.upcase
              when "GET"
                Net::HTTP::Get.new(uri.request_uri, headers)
              when "POST"
                req = Net::HTTP::Post.new(uri.request_uri, headers)
                req.body = data.to_json if data
                req
              when "DELETE"
                Net::HTTP::Delete.new(uri.request_uri, headers)
              end

    begin
      response = http.request(request)

      if response.code.to_i >= 200 && response.code.to_i < 300 && !response.body.empty?
        JSON.parse(response.body)
      elsif response.code.to_i >= 200 && response.code.to_i < 300
        true # Success but no body
      else
        logger.error "API request failed: #{response.code} - #{response.body}"
        nil
      end
    rescue StandardError => e
      logger.error "API request error: #{e.message}"
      nil
    end
  end

  def print_order_summary(orders)
    return if orders.empty?

    puts "\n📊 Order Summary:".colorize(:green)

    # Calculate totals by date
    totals_by_date = {}
    orders.each do |order|
      totals_by_date[order[:date]] ||= { count: 0, total: 0 }
      totals_by_date[order[:date]][:count] += 1
      totals_by_date[order[:date]][:total] += order[:total]
    end

    # Create summary table
    table = Terminal::Table.new do |t|
      t.title = "Orders Generated"
      t.headings = ["Date", "Order Count", "Total Sales"]

      totals_by_date.sort.each do |date, data|
        t.add_row [
          date,
          data[:count],
          "$#{(data[:total] / 100.0).round(2)}"
        ]
      end

      t.add_separator

      # Add totals row
      total_count = orders.count
      total_sales = orders.sum { |o| o[:total] }
      t.add_row ["TOTAL", total_count, "$#{(total_sales / 100.0).round(2)}"]
    end

    puts table
  end
end

if __FILE__ == $0
  begin
    CloverAutomation.new.run
  rescue StandardError => e
    puts "\nFATAL ERROR: #{e.message}".colorize(:red)
    puts e.backtrace.join("\n").colorize(:red)
    exit 1
  end
end
