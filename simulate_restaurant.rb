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

    # Step 1: Create tax rates first (needed for items)
    logger.info "Step 1: Creating tax rates..."
    @services_manager.tax.create_standard_tax_rates

    # Step 2: Create standard categories
    logger.info "Step 2: Creating restaurant categories..."
    @entity_generator.create_categories

    # Step 3: Create modifier groups
    logger.info "Step 3: Creating modifier groups..."
    @services_manager.modifier.create_common_modifier_groups

    # Step 4: Create menu items (with modifiers and tax rates)
    logger.info "Step 4: Creating menu items..."
    @entity_generator.create_items

    # Step 5: Create employee roles and employees
    logger.info "Step 5: Creating employee roles and staff..."
    roles = @services_manager.employee.create_standard_restaurant_roles
    @services_manager.employee.create_random_employees(15, roles)

    # Step 6: Create customer base
    logger.info "Step 6: Creating customer base..."
    @services_manager.customer.create_random_customers(30)

    # Step 7: Create standard tenders
    logger.info "Step 7: Creating payment tenders..."
    @services_manager.tender.create_standard_tenders

    # Step 8: Create standard discounts
    logger.info "Step 8: Creating standard discounts..."
    create_standard_discounts

    logger.info "✅ Basic restaurant setup complete"
  end

  def create_standard_discounts
    discounts = [
      {
        name: "Happy Hour",
        percentage: true,
        amount: 2000, # 20% off
        maxAmount: nil,
        minAmount: nil,
        autoApply: false
      },
      {
        name: "Senior Discount",
        percentage: true,
        amount: 1000, # 10% off
        maxAmount: nil,
        minAmount: nil,
        autoApply: false
      },
      {
        name: "Military Discount",
        percentage: true,
        amount: 1500, # 15% off
        maxAmount: nil,
        minAmount: nil,
        autoApply: false
      },
      {
        name: "$10 Off $50+",
        percentage: false,
        amount: 1000, # $10 off
        maxAmount: nil,
        minAmount: 5000, # Minimum $50 order
        autoApply: false
      },
      {
        name: "Lunch Special",
        percentage: true,
        amount: 1500, # 15% off
        maxAmount: nil,
        minAmount: nil,
        autoApply: false
      }
    ]

    created_discounts = []

    discounts.each do |discount|
      discount_data = {
        "name" => discount[:name],
        "percentage" => discount[:percentage],
        "amount" => discount[:amount],
        "maxAmount" => discount[:maxAmount],
        "minAmount" => discount[:minAmount],
        "autoApply" => discount[:autoApply]
      }

      created_discount = @services_manager.discount.create_discount(discount_data)
      if created_discount && created_discount["id"]
        logger.info "✅ Created discount: #{created_discount["name"]}"
        created_discounts << created_discount
      else
        logger.error "❌ Failed to create discount: #{discount[:name]}"
      end
    end

    created_discounts
  end

  #
  # Order Generation Methods
  #

  def generate_past_orders(days_range = DEFAULT_DAYS_RANGE, orders_per_day_range = DEFAULT_ORDERS_PER_DAY)
    logger.info "Generating orders for the past #{days_range} days..."

    # Load all required data upfront
    resources = load_all_resources
    validate_resources(resources)

    successful_orders = []

    # Create orders for each day in the range
    (1..days_range).each do |days_ago|
      past_date = Time.now - days_ago.days
      date_string = past_date.strftime("%Y-%m-%d")

      # Vary number of orders by day of week
      base_orders = case past_date.wday
                   when 5, 6 # Friday and Saturday
                     rand(15..25) # Busy weekend
                   when 0 # Sunday
                     rand(10..15) # Busy brunch
                   when 1..4 # Monday to Thursday
                     rand(5..10) # Regular weekday
                   end

      logger.info "Creating #{base_orders} orders for #{date_string}..."

      # Create orders for this date in batch
      new_orders = process_batch_orders_for_date(
        past_date,
        base_orders,
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

    num_orders.times do |i|
      # Generate timestamp within business hours
      timestamp = generate_timestamp_for_order(date, i, num_orders)

      # Generate line items
      line_items = generate_line_items(resources[:category_map], resources[:items])

      # Apply discount sometimes (20% chance)
      discount = if rand < 0.2 && resources[:discounts] && !resources[:discounts].empty?
                  resources[:discounts].sample
                end

      # Create the order with all details
      order = create_optimized_order(
        timestamp,
        resources,
        line_items,
        discount
      )

      successful_orders << order if order
    end

    successful_orders
  end

  def generate_timestamp_for_order(date, order_index, total_orders)
    # Restaurant hours: 11:00 AM to 10:00 PM
    opening_hour = 11
    closing_hour = 22

    # Calculate hour based on order index
    hour_span = closing_hour - opening_hour
    hour = opening_hour + ((order_index.to_f / total_orders) * hour_span).round

    # Add some randomness to minutes
    minutes = rand(60)

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
    num_items = rand(1..5) # Random number of items per order

    num_items.times do
      # Randomly select a category
      category = category_map.values.sample
      next unless category && category["items"]

      # Randomly select an item from the category
      item = category["items"].sample
      next unless item

      # Get modifiers for this item
      modifiers = get_item_modifiers(item["id"])
      selected_modifiers = []

      if modifiers && !modifiers.empty?
        modifiers.each do |group|
          # Skip if no modifiers in group
          next unless group["modifiers"] && !group["modifiers"].empty?

          # Determine how many modifiers to select based on min/max requirements
          min_required = group["minRequired"] || 0
          max_allowed = group["maxAllowed"] || 1
          num_to_select = rand(min_required..max_allowed)

          # Randomly select modifiers
          selected = group["modifiers"].sample(num_to_select)
          selected_modifiers.concat(selected.map { |m| { id: m["id"], name: m["name"], price: m["price"] } })
        end
      end

      # Add the item with its modifiers
      quantity = rand(1..3)
      line_items << {
        item: item,
        quantity: quantity,
        modifiers: selected_modifiers
      }
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
  def create_optimized_order(timestamp, resources, line_items, discount = nil, total_price = nil)
    # Step 1: Create the basic order
    order_data = {
      "state" => "open",
      "createdTime" => timestamp,
      "modifiedTime" => timestamp,
      "orderType" => {
        "id" => "DINE_IN" # Can be DINE_IN, TAKE_OUT, DELIVERY
      }
    }

    # Add employee if available
    if resources[:employees] && !resources[:employees].empty?
      order_data["employee"] = { "id" => resources[:employees].sample["id"] }
    end

    # Add customer if available (80% chance)
    if resources[:customers] && !resources[:customers].empty? && rand < 0.8
      order_data["customer"] = { "id" => resources[:customers].sample["id"] }
    end

    # Create the order
    order = @services_manager.order.create_order(order_data)
    return false unless order && order["id"]

    # Step 2: Add line items with modifiers
    line_items.each do |line_item|
      item = line_item[:item]
      quantity = line_item[:quantity]
      modifiers = line_item[:modifiers]

      line_item_data = {
        "item" => { "id" => item["id"] },
        "name" => item["name"],
        "price" => item["price"],
        "printed" => false,
        "quantity" => quantity
      }

      # Add modifiers if present
      if modifiers && !modifiers.empty?
        line_item_data["modifications"] = modifiers.map do |mod|
          {
            "modifier" => { "id" => mod[:id] },
            "name" => mod[:name],
            "price" => mod[:price]
          }
        end
      end

      # Create the line item
      @services_manager.order.create_line_item(order["id"], line_item_data)
    end

    # Step 3: Calculate totals
    subtotal = calculate_total_price(line_items)
    tax_amount = calculate_tax_amount(line_items)
    total = subtotal + tax_amount

    # Step 4: Apply discount if present
    if discount
      discount_amount = calculate_discount_amount(discount, subtotal)
      if discount_amount > 0
        @services_manager.order.apply_discount(order["id"], discount["id"], discount_amount)
        total -= discount_amount
      end
    end

    # Step 5: Process payment
    if total > 0
      # Select a tender (prefer non-card tenders in sandbox)
      tender = resources[:tenders].find { |t| !t["label"].downcase.include?("card") } || resources[:tenders].first
      return false unless tender

      # Add tip (15-25% chance)
      tip_percentage = rand(15..25)
      tip_amount = ((total * tip_percentage) / 100.0).round

      # Process the payment with tip
      payment_processed = process_payment(
        order["id"],
        order_data.dig("employee", "id"),
        tender["id"],
        total + tip_amount,
        timestamp
      )

      return false unless payment_processed

      # Update order state
      @services_manager.order.update_order(order["id"], { "state" => "paid" })
    end

    order
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

  def get_item_modifiers(item_id)
    response = make_request(:get, "items/#{item_id}/modifier_groups")
    return [] unless response && response["elements"]

    response["elements"].map do |group|
      # Get modifiers for this group
      modifiers_response = make_request(:get, "modifier_groups/#{group["id"]}/modifiers")
      group["modifiers"] = modifiers_response["elements"] if modifiers_response && modifiers_response["elements"]
      group
    end
  end

  def calculate_tax_amount(line_items)
    total_tax = 0

    line_items.each do |line_item|
      item = line_item[:item]
      quantity = line_item[:quantity]
      base_price = item["price"] * quantity

      # Add modifier prices
      modifier_total = line_item[:modifiers].sum { |m| m[:price].to_i }
      item_total = base_price + modifier_total

      # Calculate tax based on tax rates
      if item["taxRates"]
        item["taxRates"].each do |tax_rate|
          rate_percentage = tax_rate["rate"].to_f / 10000.0 # Convert basis points to percentage
          total_tax += (item_total * rate_percentage).round
        end
      end
    end

    total_tax
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
