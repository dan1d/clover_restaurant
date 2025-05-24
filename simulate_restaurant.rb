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
require "optparse"

class RestaurantSimulator
  # Constants for order generation
  DEFAULT_DAYS_RANGE = 7
  DEFAULT_ORDERS_PER_DAY = (5..15)

  attr_reader :services_manager, :entity_generator, :logger

  def initialize
    @config = CloverRestaurant::Config.new
    @logger = @config.logger
    setup_services
  end

  def run(options = {})
    print_header

    @logger.info "Starting full setup (always resets everything)..."

    begin
      setup_entities
      print_summary

      if options[:generate_orders]
        @logger.info "Proceeding to generate past orders and payments..."
        days_to_generate = options.fetch(:days_range, 7) # Default to 7 days
        orders_per_day = options.fetch(:orders_per_day, {min: 5, max: 15}) # Default to 5-15 orders

        # Convert orders_per_day to a range if it's a hash
        orders_per_day_range = if orders_per_day.is_a?(Hash) && orders_per_day[:min] && orders_per_day[:max]
                                 (orders_per_day[:min]..orders_per_day[:max])
                               else
                                 orders_per_day # Use as is if already a range or single number
                               end

        generate_past_orders(days_to_generate, orders_per_day_range)
        @logger.info "✅ Order and payment generation completed."
      else
        @logger.info "Skipping order generation. Use --generate-orders to enable."
      end

    rescue StandardError => e
      @logger.error "FATAL ERROR: #{e.message}"
      @logger.error e.backtrace.join("\n")
      exit 1
    end
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

  def setup_services
    @services_manager = CloverRestaurant::CloverServicesManager.new(@config)
    @entity_generator = CloverRestaurant::DataGeneration::EntityGenerator.new(
      @services_manager.config, @services_manager
    )
    @api_token = @services_manager.config.api_token
    @merchant_id = @services_manager.config.merchant_id
    @environment = @services_manager.config.environment.chomp("/")
  end

  def print_header
    puts "\n" + "=" * 80
    puts "CLOVER AUTOMATION".center(80)
    puts "=" * 80 + "\n\n"
    puts "Merchant ID: #{@config.merchant_id}"
    puts "Environment: #{@config.environment}"
  end

  def setup_entities
    @logger.info "Setting up Clover entities (full reset)..."

    # Store created entities for use in later steps
    @created_entities = {
      tax_rates: [],
      categories: [],
      modifier_groups: [],
      menu_items: [],
      discounts: [],
      roles: [],
      employees: [],
      shifts: [],
      customers: [],
      order_types: []
    }

    @logger.info "Step 1: Creating tax rates..."
    setup_tax_rates

    @logger.info "Step 2: Creating categories..."
    setup_categories

    @logger.info "Step 3: Creating modifier groups..."
    setup_modifier_groups

    @logger.info "Step 4: Creating menu items..."
    setup_menu_items

    @logger.info "Step 5: Creating discounts..."
    setup_discounts

    @logger.info "Step 6: Creating roles..."
    setup_roles

    @logger.info "Step 7: Creating employees..."
    setup_employees

    @logger.info "Step 8: Creating shifts..."
    setup_shifts

    @logger.info "Step 9: Creating customers..."
    setup_customers

    @logger.info "Step 10: Creating order types..."
    setup_order_types

    @logger.info "✅ All entities created successfully!"
  end

  def setup_tax_rates
    @logger.info "Creating standard tax rates..."
    created_rates = @services_manager.tax.create_standard_tax_rates

    if created_rates && created_rates.any?
      @logger.info "Successfully created or verified #{created_rates.size} standard tax rates."
      @created_entities[:tax_rates] = created_rates
    end
  end

  def setup_categories
    @logger.info "Creating standard categories..."
    categories = @services_manager.inventory.create_standard_categories
    @created_entities[:categories] = categories.map { |cat| {"clover_id" => cat["id"], "name" => cat["name"], "data" => cat} }
    @logger.info "Created #{categories.size} categories"
  end

  def setup_modifier_groups
    @logger.info "Creating standard modifier groups..."
    groups = @services_manager.inventory.create_standard_modifier_groups
    @created_entities[:modifier_groups] = groups.map { |group| {"clover_id" => group["id"], "name" => group["name"], "data" => group} }
    @logger.info "Created #{groups.size} modifier groups"
  end

  def setup_menu_items
    @logger.info "Creating menu items..."
    categories = @created_entities[:categories]
    items = @services_manager.inventory.create_sample_menu_items(categories)
    @created_entities[:menu_items] = items.map { |item| {"clover_id" => item["id"], "name" => item["name"], "data" => item} }
    @logger.info "Created #{items.size} menu items"
  end

  def setup_discounts
    @logger.info "Creating standard discounts..."
    created_discounts = @services_manager.discount.create_standard_discounts

    if created_discounts && created_discounts.is_a?(Array)
      @created_entities[:discounts] = created_discounts.select { |d| d.is_a?(Hash) && d["id"] }
      @logger.info "Created #{@created_entities[:discounts].size} discounts"
    else
      @logger.warn "No discounts created or unexpected format: #{created_discounts.inspect}"
      @created_entities[:discounts] = []
    end
  end

  def setup_roles
    @logger.info "Creating standard roles..."
    roles = @services_manager.employee.create_standard_restaurant_roles
    @created_entities[:roles] = roles.map { |role| {"clover_id" => role["id"], "name" => role["name"], "data" => role} }
    @logger.info "Created #{roles.size} roles"
  end

  def setup_employees
    @logger.info "Creating employees..."
    roles = @created_entities[:roles]
    employees = @services_manager.employee.create_random_employees(15, roles)
    @created_entities[:employees] = employees.map { |emp| {"clover_id" => emp["id"], "name" => emp["name"], "data" => emp} }
    @logger.info "Created #{employees.size} employees"
  end

  def setup_shifts
    @logger.info "Creating shifts..."
    employees = @created_entities[:employees]
    shifts = []
    employees.each do |employee|
      shift = @services_manager.employee.clock_in(employee["clover_id"])
      if shift
        shifts << {"clover_id" => shift["id"], "name" => "#{employee["name"]}_shift", "data" => shift}
      end
    end
    @created_entities[:shifts] = shifts
    @logger.info "Created #{shifts.size} shifts"
  end

  def setup_customers
    @logger.info "Creating customers..."
    customers = @services_manager.customer.create_random_customers(30) # Create 30 random customers
    valid_customers = []

    customers.each do |customer|
      if customer && customer["id"]
        display_name = if customer["firstName"] && customer["lastName"]
                         "#{customer["firstName"]} #{customer["lastName"]}"
                       elsif customer["firstName"]
                         customer["firstName"]
                       elsif customer["emailAddresses"]&.first&.[]("emailAddress")
                         customer["emailAddresses"].first["emailAddress"]
                       else
                         "Customer #{customer["id"]}"
                       end
        valid_customers << {"clover_id" => customer["id"], "name" => display_name, "data" => customer}
      else
        @logger.warn "Failed to create or retrieve ID for a customer: #{customer.inspect}"
      end
    end

    @created_entities[:customers] = valid_customers
    @logger.info "Created #{valid_customers.size} customers"
  end

  def setup_order_types
    @logger.info "Creating order types..."

    # Try to get existing order types first
    existing_order_types_response = @services_manager.merchant.get_order_types
    if existing_order_types_response && existing_order_types_response["elements"]&.any?
      @logger.info "Found #{existing_order_types_response["elements"].size} existing order types."
      order_types = existing_order_types_response["elements"].map do |ot|
        {"clover_id" => ot["id"], "name" => ot["label"] || ot["name"], "data" => ot}
      end
      @created_entities[:order_types] = order_types
      return
    end

    @logger.info "No existing order types found, creating default ones..."
    default_order_types = [
      { name: "Dine In", label: "Dine In", taxable: true, isDefault: true },
      { name: "Take Out", label: "Take Out", taxable: true, isDefault: false },
      { name: "Delivery", label: "Delivery", taxable: true, isDefault: false }
    ]

    created_order_types = []
    default_order_types.each do |ot_data|
      begin
        created_ot = @services_manager.merchant.create_order_type(ot_data)
        if created_ot && created_ot["id"]
          @logger.info "✅ Successfully created order type: #{created_ot["label"]}"
          created_order_types << {"clover_id" => created_ot["id"], "name" => created_ot["label"], "data" => created_ot}
        else
          @logger.error "❌ Failed to create order type: #{ot_data[:label]}. Response: #{created_ot.inspect}"
        end
      rescue StandardError => e
        @logger.error "❌ Error creating order type #{ot_data[:label]}: #{e.message}"
      end
    end

    @created_entities[:order_types] = created_order_types
    @logger.info "Created #{created_order_types.size} order types"
  end

  def print_summary
    table = Terminal::Table.new do |t|
      t.title = "Setup Summary"
      t.headings = ['Entity Type', 'Count']

      @created_entities.each do |type, entities|
        t.add_row [type.to_s.gsub('_', ' ').titleize, entities.size]
      end
    end

    puts "\n" + table.to_s + "\n"
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
                     rand(orders_per_day_range) # Regular weekday
                   end

      logger.info "Creating #{base_orders} orders for #{date_string}..."

      # Create orders for this date in batch
      new_orders_for_date = process_batch_orders_for_date( # Renamed to avoid confusion
        past_date,
        base_orders,
        resources
      )

      successful_orders.concat(new_orders_for_date) if new_orders_for_date # Ensure it's an array
    end

    # Print summary table
    print_order_summary(successful_orders)
  end

  def load_all_resources
    logger.info "Loading resources from Clover..."

    resources = {
      items: fetch_with_rescue { @created_entities[:menu_items] },
      categories: fetch_with_rescue { @created_entities[:categories] },
      customers: fetch_with_rescue { @created_entities[:customers] },
      employees: fetch_with_rescue { @created_entities[:employees] },
      tenders: filter_safe_tenders(fetch_with_rescue { @services_manager.tender.get_tenders }),
      discounts: fetch_with_rescue { @created_entities[:discounts] },
      tax_rates: fetch_with_rescue { @created_entities[:tax_rates] }
    }

    # Pre-organize items by category to avoid duplicate processing
    all_items_map = create_item_map(resources[:items])
    @logger.info "DEBUG LOAD_ALL_RESOURCES: local all_items_map type: #{all_items_map.class}, size: #{all_items_map.size}, content: #{all_items_map.inspect[0..200]}" # DEBUG
    category_map = create_category_map(resources[:categories], all_items_map)

    resources[:all_items_map] = all_items_map
    resources[:category_map] = category_map
    @logger.info "DEBUG LOAD_ALL_RESOURCES: resources[:all_items_map] type: #{resources[:all_items_map].class}, size: #{resources[:all_items_map].size}, content: #{resources[:all_items_map].inspect[0..200]}" # DEBUG

    @logger.info "Resources loaded successfully"
    resources
  end

  def filter_safe_tenders(tenders)
    # Filter out credit/debit card tenders that won't work in sandbox
    safe_tenders = tenders.reject do |tender|
      tender["label"] == "Credit Card" ||
        tender["label"] == "Debit Card" ||
        (tender["labelKey"] && (tender["labelKey"].include?("credit") || tender["labelKey"].include?("debit")))
    end

    # Log available tender types for debugging
    @logger.info "Available tender types:"
    tenders.each do |tender|
      @logger.info "  - #{tender["label"]} (#{tender["labelKey"]}) - Enabled: #{tender["enabled"]}"
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

  def create_category_map(categories, all_items_map)
    category_map = {}

    # Initialize each category in the map
    categories.each do |category|
      category_map[category["id"]] = []
    end

    # Add items to their respective categories
    all_items_map.each_value do |item|
      next unless item["categories"] && item["categories"]["elements"]

      item["categories"]["elements"].each do |category|
        category_id = category["id"]
        category_map[category_id] ||= []
        category_map[category_id] << item
      end
    end

    # For items without categories, create a "Miscellaneous" category
    uncategorized = all_items_map.values.select { |item| !item["categories"] || item["categories"]["elements"].empty? }
    category_map["misc"] = uncategorized unless uncategorized.empty?

    @logger.info "Created category map with #{category_map.keys.size} categories"
    category_map
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
    orders_for_this_batch = [] # Changed variable name

    num_orders.times do |i|
      # Generate timestamp within business hours
      timestamp = generate_timestamp_for_order(date, i, num_orders)

      # Generate line items
      line_items = generate_line_items(resources[:category_map], resources[:items], resources[:discounts])

      # Apply discount sometimes (20% chance)
      discount = nil
      if resources[:discounts] && !resources[:discounts].empty?
        discount = resources[:discounts].sample
        @logger.info "Selected discount to attempt: #{discount['name']}" if discount
      end

      # Create the order with all details
      order = create_optimized_order(
        timestamp,
        resources,
        line_items,
        discount
      )

      #MODIFICATION START: Add order to list if it was created, regardless of payment
      if order && order["id"]
        order_details_for_summary = {
          id: order["id"],
          date: date.strftime("%Y-%m-%d"),
          time: Time.at(timestamp / 1000).strftime("%H:%M:%S"), # Added seconds for more detail
          total: order["total"] || 0, # Use order total which should be updated by create_optimized_order
          # Attempt to get employee display name, fallback to name, then ID
          employee: (resources[:employees].find { |emp| emp["id"] == order.dig("employee", "id") }&.[]("displayName") ||
                     resources[:employees].find { |emp| emp["id"] == order.dig("employee", "id") }&.[]("name") ||
                     order.dig("employee", "id") || "N/A"),
          # Attempt to get tender label, fallback to ID
          tender: ("N/A"), # Placeholder, will be updated if payment is successful
          payment_status: "Pending" # Initial status
        }

        # If payment was attempted and successful inside create_optimized_order,
        # it might return payment details or update the order object.
        # For now, we assume create_optimized_order returns the order object.
        # We will update payment_status and tender if payment succeeds.
        # This part might need refinement based on what create_optimized_order returns regarding payment.

        orders_for_this_batch << order_details_for_summary
      elsif order == false # Explicitly check for false if create_optimized_order returns that on failure
        logger.warn "Order creation failed for one attempt on #{date.strftime('%Y-%m-%d')}."
      else
        logger.warn "Order creation attempt returned unexpected value: #{order.inspect} on #{date.strftime('%Y-%m-%d')}."
      end
      #MODIFICATION END
    end

    orders_for_this_batch # Return the collected orders for this batch
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
      line_items_data = generate_line_items(resources[:category_map], resources[:items], resources[:discounts])
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

  def generate_line_items(category_map, all_items_map, available_discounts = [])
    # Ensure all_items_map is logged with its actual variable name in this scope
    @logger.info "DEBUG GENERATE_LINE_ITEMS: Entry: received all_items_map type: #{all_items_map.class}, size: #{all_items_map.size rescue 'N/A'}, content: #{all_items_map.inspect[0..200]}" # DEBUG
    line_items = []
    num_items_in_order = rand(5..6) # Number of distinct items in an order
    @logger.info "Generating #{num_items_in_order} line items for the order."

    # Ensure all_items_map contains detailed item objects, not just IDs
    # This might require adjustment if all_items_map passed in is just basic info

    # Get a sample of item IDs from the values of the category_map (which should be arrays of item IDs or objects)
    available_item_ids_or_objects = category_map.values.flatten.uniq
    selected_item_ids_or_objects = available_item_ids_or_objects.sample(num_items_in_order)

    selected_item_ids_or_objects.each do |item_ref|
      # MODIFICATION: Use helper to get full item details
      item_details = get_item_details_for_simulation(item_ref, all_items_map)
      unless item_details && item_details["id"] && item_details["price"]
        @logger.error "Could not get valid details for item_ref: #{item_ref.inspect}. Skipping this item."
        next
      end
      item_actual_id = item_details["id"]
      item_price = item_details["price"].to_i # Ensure integer for calculations

      quantity = rand(4..8)
      selected_modifiers = []
      modifiers = item_details["modifierGroups"] && item_details["modifierGroups"]["elements"]

      if modifiers && !modifiers.empty?
        modifiers.each do |group|
          next unless group["modifiers"] && !group["modifiers"].empty?
          min_required = group["minRequired"] || 0
          max_allowed = group["maxAllowed"] || group["modifiers"].size
          min_required = [min_required, max_allowed, group["modifiers"].size].min
          num_to_select = 0
          if min_required > 0
            num_to_select = rand(min_required..[max_allowed, group["modifiers"].size].min)
          elsif max_allowed > 0 && group["modifiers"].any?
            num_to_select = rand(1..[max_allowed, group["modifiers"].size].min)
          end
          if num_to_select > 0
            selected = group["modifiers"].sample(num_to_select)
            selected_modifiers.concat(selected.map { |m| { "modifier" => { "id" => m["id"] } } })
            @logger.info "Selected #{selected.size} modifier(s) from group '#{group["name"]}' for item '#{item_actual_id}': #{selected.map { |m| m["name"] }.join(", ")}"
          end
        end
      end

      # MODIFICATION: Attempt to add a line-item specific discount (e.g. 20% chance)
      line_item_discount_data = nil
      if rand < 0.2 && available_discounts && available_discounts.any? && item_price > 0
        chosen_discount = available_discounts.sample
        # For simplicity, let's make it a small fixed amount, like $1 or 10% of item price, whichever is smaller
        # Ensure this amount is positive here; OrderService will make it negative.
        discount_amount_value = [100, (item_price * 0.1).round].min
        if discount_amount_value > 0
            line_item_discount_data = {
                discount_id: chosen_discount["id"],
                discount_name: chosen_discount["name"],
                calculated_amount: discount_amount_value
            }
            @logger.info "Item '#{item_details["name"]}' will attempt line item discount: '#{chosen_discount["name"]}' for $#{discount_amount_value/100.0}"
        end
      end

      line_items << {
        item_id: item_actual_id,
        name: item_details["name"],
        price: item_price,
        quantity: quantity,
        modifications: selected_modifiers,
        tax_rates: item_details["taxRates"],
        line_item_discount_info: line_item_discount_data # Store discount info
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
  def create_optimized_order(timestamp, resources, prepared_line_items, order_discount = nil, total_price_pre_order_discount = nil)
    # Step 1: Define Order Type and Note
    order_type_to_use = @created_entities[:order_types]&.sample
    unless order_type_to_use && (order_type_to_use["clover_id"] || order_type_to_use["id"])
      @logger.error "No order types available in state or missing ID. Cannot create order."
      return false
    end
    actual_order_type_id = order_type_to_use["clover_id"] || order_type_to_use["id"]

    # Define order_note
    possible_notes = ["Special instructions for the chef.", "Customer in a hurry.", "Birthday celebration, add a candle if possible.", nil, "Allergic to peanuts.", nil]
    order_note = possible_notes.sample
    @logger.info "Order note selected: #{order_note || 'None'}"

    # Employee for the order
    employee_for_order = resources[:employees]&.sample
    unless employee_for_order && employee_for_order["id"]
      @logger.error "No employees available in resources. Cannot assign employee to order."
      # Depending on requirements, you might assign a default, or fail. For now, let's try to proceed.
      # employee_for_order_id = nil # Or fetch a default if critical
    end
    employee_for_order_id = employee_for_order["id"] if employee_for_order

    order_shell_data = {
      # "employee" => { "id" => resources[:employees].sample["id"] }, # Replaced by safer logic above
      "note" => order_note,
      "orderType" => { "id" => actual_order_type_id },
      "state" => "open",
      "createdTime" => timestamp,
      "line_items" => prepared_line_items.map do |pli|
        {
          item_id: pli[:item_id],
          quantity: pli[:quantity],
          modifications: pli[:modifications],
          notes: pli[:name]
        }
      end
    }
    # Add employee to payload only if successfully found
    order_shell_data["employee"] = { "id" => employee_for_order_id } if employee_for_order_id

    created_order_object = @services_manager.order.create_order(order_shell_data)
    return false unless created_order_object && created_order_object["id"]
    order_id = created_order_object["id"]

    @logger.info "Order shell and initial line items created. Order ID: #{order_id}"
    @logger.info "Initial order object from create_order: #{created_order_object.inspect}"

    # Fetch the order again to get line item IDs assigned by Clover, as create_order returns the order shell
    # The line items within created_order_object from create_order might not have their final Clover IDs immediately
    # or might not be the full objects. So, a fresh get_order is safer.
    current_order_details = @services_manager.order.get_order(order_id)
    unless current_order_details && current_order_details["lineItems"] && current_order_details["lineItems"]["elements"]
        @logger.error "Failed to fetch order details with line item IDs for order #{order_id} after creation. Cannot apply line item discounts."
        # Decide if we should return false or continue without line item discounts
    else
        @logger.info "Fetched order details for line item discount processing: #{current_order_details.inspect}"
        # Match prepared_line_items (which have our discount_info) with actual created line items from Clover
        # This matching can be tricky. Simplest might be by item_id and hope there are no duplicates of the *same* item_id
        # in the `prepared_line_items` before being sent. If `generate_line_items` can produce multiple distinct entries
        # for the *same* product (e.g. one with discount, one without), this will need careful handling.
        # For now, assume each entry in `prepared_line_items` corresponds to one in `current_order_details.lineItems.elements`
        # based on the item's original ID.

        clover_line_items = current_order_details["lineItems"]["elements"]

        prepared_line_items.each_with_index do |prepared_li, index|
            if prepared_li[:line_item_discount_info]
                # Find the corresponding Clover line item. This is a potential point of failure if order differs.
                # A robust way would be if `add_line_item` in OrderService returned the created line item ID
                # and `create_order` could return an array of these.
                # For now, let's try to find by original item_id and assume order is preserved, or find first match.
                # This is a simplification and might not work if multiple line items use the same catalog item ID.

                # Attempt to find a match based on the original item_id from `prepared_li`
                # and hope that `clover_line_items` are in a somewhat predictable order or have unique item IDs for this order.
                # This is a weak link.
                matching_clover_li = clover_line_items.find do |cli|
                    cli["item"] && cli["item"]["id"] == prepared_li[:item_id] && \
                    !cli.key?(:_processed_for_discount) # Mark as processed to avoid reapplying to same if multiple identical items
                end

                if matching_clover_li
                    clover_li_id = matching_clover_li["id"]
                    discount_info = prepared_li[:line_item_discount_info]
                    @logger.info "Attempting to apply line item discount '#{discount_info[:discount_name]}' to Clover line item ID '#{clover_li_id}' (Original item ID: '#{prepared_li[:item_id]}')"
                    @services_manager.order.apply_discount_to_line_item(
                        order_id,
                        clover_li_id,
                        discount_info[:discount_id],
                        discount_info[:calculated_amount]
                    )
                    matching_clover_li[:_processed_for_discount] = true # Mark it
                else
                    @logger.warn "Could not find matching Clover line item for prepared item ID '#{prepared_li[:item_id]}' to apply line item discount. Order structure might have changed or item not found."
                end
            end
        end

        # Clean up our temporary marker
        clover_line_items.each { |cli| cli.delete(:_processed_for_discount) }
        # Re-fetch order details after line item discounts are applied to reflect them
        current_order_details = @services_manager.order.get_order(order_id)
    end

    # Apply order-level discount IF ONE WAS SELECTED (current logic already tries this)
    # MODIFICATION: ensure order_discount is not nil before attempting to apply
    # Use total_price_pre_order_discount if provided, otherwise re-calculate if necessary
    # The 'discount' parameter is now 'order_discount'
    # The 'total_price' parameter is now 'total_price_pre_order_discount'

    calculated_total_pre_order_discount = if total_price_pre_order_discount.nil?
                                            current_order_details["total"] || 0 # Or recalculate from line items
                                          else
                                            total_price_pre_order_discount
                                          end

    if order_discount && order_discount["id"]
      # discount_amount = calculate_discount_amount(order_discount, total_price)
      # Corrected: Use calculated_total_pre_order_discount for order-level discount calculation
      discount_amount_for_order = calculate_discount_amount(order_discount, calculated_total_pre_order_discount)

      if discount_amount_for_order > 0
        @logger.info "Attempting to apply order discount ID '#{order_discount["id"]}' of #{discount_amount_for_order} to order '#{current_order_details['id']}' (pre-discount total: #{calculated_total_pre_order_discount})"
        applied_discount_line = @services_manager.order.apply_discount(current_order_details["id"], order_discount["id"], discount_amount_for_order)
        if applied_discount_line && applied_discount_line["id"]
          @logger.info "Successfully applied order discount. Relying on order's current total from Clover for payment."
          # Re-fetch order to get the most up-to-date total after discount application
          current_order_details = @services_manager.order.get_order(current_order_details["id"]) # IMPORTANT re-fetch
          total_after_order_discount = current_order_details["total"] # This should be the true total from Clover
        else
          @logger.warn "Failed to apply order discount or no confirmation of discount effect on total. Using pre-discount total for payment or manual adjustment."
          # total_after_order_discount = total_price # Fallback
          total_after_order_discount = current_order_details["total"] # Rely on whatever total Clover has at this point
        end
      else
        # total_after_order_discount = total_price
        total_after_order_discount = current_order_details["total"] # No order discount applied, use current total
      end
    else
      # total_after_order_discount = total_price
      total_after_order_discount = current_order_details["total"] # No order discount attempted, use current total
    end

    # DEBUG LOGGING START
    logger.info "DEBUG: Before payment block for Order ID #{current_order_details['id']}:"
    # logger.info "  total_from_order: #{total_price}"
    logger.info "  calculated_total_pre_order_discount: #{calculated_total_pre_order_discount}"
    # logger.info "  discount_amount (if discount applied): #{discount_amount || 'N/A'}"
    logger.info "  discount_amount_for_order (order-level): #{discount_amount_for_order || 'N/A'}"
    # logger.info "  total_after_discount: #{total_after_discount}"
    logger.info "  total_after_order_discount (used for payment calcs): #{total_after_order_discount}"
    logger.info "  FULL ORDER DETAILS PRE-PAYMENT: #{current_order_details.to_json}"
    # DEBUG LOGGING END

    # Step 5: Process payment
    # if total_after_discount > 0 # Use total_after_discount for payment
    if total_after_order_discount > 0 # MODIFIED: Use the total after order-level discount for payment logic

      # Select a tender (prefer non-card tenders in sandbox)
      # Ensure tenders are available - prioritize external payment and cash
      tender = resources[:tenders].find { |t| t["labelKey"] == "com.clover.tender.external_payment" && t["enabled"] } ||
               resources[:tenders].find { |t| t["labelKey"] == "com.clover.tender.cash" } ||
               resources[:tenders].find { |t| !t["label"].downcase.include?("card") } ||
               resources[:tenders].first
      unless tender
        @logger.error "No suitable tender found for payment. Order: #{current_order_details['id']}"
        # Update order with a note about payment failure due to no tender
        @services_manager.order.update_order(current_order_details["id"], { "note" => "Payment failed: No suitable tender." })
        return current_order_details # Return order even if payment fails, summary will show pending
      end

      # Define employee_id_for_payment (ensure this is defined before use)
      employee_id_for_payment = current_order_details.dig("employee", "id") || resources[:employees]&.sample&.[]("id")
      unless employee_id_for_payment
         @logger.warn "No employee ID found for payment on order #{current_order_details['id']}. Payment might fail or use a default."
         # Fallback if truly no employee can be found (should be rare if setup is complete)
         employee_id_for_payment = @created_entities[:employees]&.sample&.[]("id")
      end

      tip_percentage = rand(15..25) # Tip between 15% and 25%
      # tip_amount_for_payment_service = ((total_after_discount * tip_percentage) / 100.0).round
      tip_amount_for_payment_service = ((total_after_order_discount * tip_percentage) / 100.0).round
      tip_amount_for_payment_service = [0, tip_amount_for_payment_service].max

      tax_amount_for_payment_service = calculate_tax_amount(current_order_details["lineItems"]&.[]("elements"), resources[:tax_rates])

      # total_for_payment_service = total_after_discount + tip_amount_for_payment_service
      total_for_payment_service = total_after_order_discount + tip_amount_for_payment_service

      logger.info "DEBUG: Values for PaymentService call on Order ID #{current_order_details['id']}:"
      # logger.info "  total_after_discount (subtotal used for tip/tax calcs): #{total_after_discount}"
      logger.info "  total_after_order_discount (subtotal used for tip/tax calcs): #{total_after_order_discount}"
      logger.info "  tip_percentage: #{tip_percentage}%"
      logger.info "  calculated tip_amount_for_payment_service (to PaymentService): #{tip_amount_for_payment_service}"
      logger.info "  calculated tax_amount_for_payment_service (to PaymentService): #{tax_amount_for_payment_service}"
      logger.info "  total_for_payment_service (subtotal+tip to PaymentService 'amount' field): #{total_for_payment_service}"
      logger.info "  employee_id_for_payment (to PaymentService): #{employee_id_for_payment}"
      logger.info "  selected_tender_id (used inside PaymentService): #{tender ? tender['id'] : 'N/A'}" # Tender is used within PaymentService now
      # DEBUG LOGGING END

      payment_response = @services_manager.payment.process_payment(
        current_order_details["id"],          # order_id
        total_for_payment_service,            # total_amount (subtotal + tip)
        employee_id_for_payment,              # employee_id
        timestamp,                            # past_timestamp
        tip_amount_for_payment_service,       # tip_amount
        tax_amount_for_payment_service        # tax_amount
      )

      unless payment_response && payment_response["id"]
        @logger.error "Payment processing failed for order '#{current_order_details['id']}'. Response: #{payment_response.inspect}"
        # Update order with a note about payment failure
        @services_manager.order.update_order(current_order_details["id"], { "note" => "Payment failed: #{payment_response.inspect}" })
        #MODIFICATION: Return the order object even if payment fails, so it can be logged in summary
        return current_order_details # Return order, summary will show payment as pending/failed
      end
      payment_id = payment_response["id"]
      paid_amount = payment_response["amount"] # This is the subtotal part of the payment

      # Update order state to paid (let Clover determine paymentState)
      @services_manager.order.update_order(current_order_details["id"], { "state" => "paid" })
      #MODIFICATION: Add payment details to the order object for summary
      current_order_details["payment_status"] = "Paid (Attempted)" # Reflect that payment was made
      current_order_details["tender_label"] = tender["label"] # Use the fetched tender's label
      current_order_details["payment_id"] = payment_id
      current_order_details["tip_amount"] = tip_amount_for_payment_service # Log tip
      current_order_details["tax_amount"] = tax_amount_for_payment_service # Log tax

      # Simulate a partial refund (e.g., 50% chance now)
      # if paid_amount && paid_amount > 0 # Ensure there's something to refund (paid_amount comes from payment_response["amount"])
      #   refund_amount = (paid_amount * rand(0.1..0.5)).round # Refund 10-50% of the payment subtotal
      #   if refund_amount > 0
      #     @logger.info "Attempting to issue a partial refund of $#{refund_amount / 100.0} for payment '#{payment_id}' on order '#{current_order_details['id']}'."
      #     @services_manager.payment.create_refund(payment_id, current_order_details["id"], refund_amount)
      #   end
      # end

    else # total_after_discount <= 0
      @logger.warn "Total amount for order '#{current_order_details['id']}' is not positive (#{total_after_order_discount}), skipping payment."
      # Update order with a note about no payment processed
      @services_manager.order.update_order(current_order_details["id"], { "note" => "No payment processed: Total was not positive." })
      #MODIFICATION: Add payment status to the order object for summary
      current_order_details["payment_status"] = "NoPayment (ZeroTotal)"
      current_order_details["tip_amount"] = 0 # No tip if no payment
      current_order_details["tax_amount"] = 0 # No tax if no payment

    end

    #MODIFICATION: If order was returned (even if payment fails), update its attributes from current_order_details
    # Fetch the LATEST order details after any payment attempt or note update
    # This re-fetch IS important here to get the absolute latest state after payment/notes.
    final_order_details = @services_manager.order.get_order(current_order_details["id"])
    logger.info "DEBUG: FULL ORDER DETAILS POST-PAYMENT/POST-NOTE: #{final_order_details.to_json}"

    # Ensure current_order_details (which is the 'order' object we've been working with)
    # gets updated with any final details for the summary.
    if final_order_details
      current_order_details["total"] = final_order_details["total"] || 0
      current_order_details["paymentState"] = final_order_details["paymentState"]
      current_order_details["note"] = final_order_details["note"]
      # Keep the original total_from_order for debugging if needed, but ensure 'total' is the final one.
      current_order_details["original_total_from_order_service"] = calculated_total_pre_order_discount #MODIFIED: Use correct pre-discount total
    end

    current_order_details # Return the (potentially modified) order object
  end

  def process_payment(order_id, employee_id, tender_id, amount, timestamp) # This local method is unused.
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
    orders.each do |order_summary| # Iterate over order_summary hashes
      next unless order_summary && order_summary[:date] && order_summary.key?(:total)
      totals_by_date[order_summary[:date]] ||= { count: 0, total_paid: 0, total_pending: 0 } # Adjusted for payment status
      totals_by_date[order_summary[:date]][:count] += 1
      if order_summary[:payment_status] == "Paid"
        totals_by_date[order_summary[:date]][:total_paid] += (order_summary[:total] || 0)
      else
        totals_by_date[order_summary[:date]][:total_pending] += (order_summary[:total] || 0)
      end
    end

    # Create summary table
    table = Terminal::Table.new do |t|
      t.title = "Orders Generated"
      #MODIFICATION: Updated headings for clarity
      t.headings = ["Date", "Order ID", "Time", "Total", "Tip", "Tax", "Employee", "Tender", "Payment Status", "Payment ID"] # Added Tip, Tax, Payment ID

      #MODIFICATION: Iterate through orders (which are now hashes) and populate rows
      orders.sort_by { |o| [o[:date], o[:time]] }.each do |order_summary|
        t.add_row [
          order_summary[:date],
          order_summary[:id],
          order_summary[:time],
          "$#{(order_summary[:total] / 100.0).round(2)}",
          "$#{((order_summary[:tip_amount] || 0) / 100.0).round(2)}", # Display tip
          "$#{((order_summary[:tax_amount] || 0) / 100.0).round(2)}", # Display tax
          order_summary[:employee],
          order_summary[:tender_label] || order_summary[:tender] || "N/A", # Use tender_label if available
          order_summary[:payment_status],
          order_summary[:payment_id] || "N/A" # Display payment ID
        ]
      end

      t.add_separator

      # Add totals summary by date
      totals_by_date.sort.each do |date, data|
        t.add_row [date, "#{data[:count]} orders", "",
                   "Paid: $#{(data[:total_paid] / 100.0).round(2)}",
                   "Tips: $#{(data[:total_paid] / 100.0).round(2)}", # Show total tips
                   "Taxes: $#{(data[:total_paid] / 100.0).round(2)}", # Show total taxes
                   "", "", ""]
      end

      t.add_separator

      # Add overall totals row
      total_count = orders.count
      total_sales_paid = orders.sum { |o| (o && o[:total] && o[:payment_status] == "Paid") ? o[:total] : 0 }
      total_sales_pending = orders.sum { |o| (o && o[:total] && o[:payment_status] != "Paid") ? o[:total] : 0 }
      total_tips = orders.sum { |o| (o && o[:tip_amount] && o[:payment_status] == "Paid") ? o[:tip_amount] : 0 }
      total_taxes = orders.sum { |o| (o && o[:tax_amount] && o[:payment_status] == "Paid") ? o[:tax_amount] : 0 }

      t.add_row ["TOTALS", "#{total_count} orders", "",
                 "Paid: $#{(total_sales_paid / 100.0).round(2)}",
                 "Tips: $#{(total_tips / 100.0).round(2)}", # Show total tips
                 "Taxes: $#{(total_taxes / 100.0).round(2)}", # Show total taxes
                 "Pending: $#{(total_sales_pending / 100.0).round(2)}", "", "", ""]
    end

    puts table
  end

  # MODIFICATION: Helper method to get item details, handling cache or direct fetch.
  def get_item_details_for_simulation(item_id_or_object, all_items_map)
    # Ensure all_items_map is logged with its actual variable name in this scope
    @logger.info "DEBUG GET_ITEM_DETAILS: Entry: received all_items_map type: #{all_items_map.class}, size: #{all_items_map.size rescue 'N/A'}, content: #{all_items_map.inspect[0..200]}" # DEBUG
    if item_id_or_object.is_a?(Hash)
      # Handle StateManager object structure
      if item_id_or_object["entity_type"] == "menu_item" && item_id_or_object["clover_id"]
        item_id_to_fetch = item_id_or_object["clover_id"]
        # Prefer data from all_items_map if available, as it should be from direct Clover API call
        return all_items_map[item_id_to_fetch] if all_items_map&.key?(item_id_to_fetch)
        # Fallback to item_id_or_object[\"data\"] if it exists and looks like an item
        return item_id_or_object["data"] if item_id_or_object["data"] && item_id_or_object["data"]["id"]
        # Else, fetch using the clover_id
        @logger.warn "Item ID #{item_id_to_fetch} (from StateManager object) not in pre-loaded map, fetching directly..."
        return @services_manager.inventory.get_item(item_id_to_fetch)
      elsif item_id_or_object['id'] # Already a detailed item object (e.g., from direct API call)
        return item_id_or_object
      end
    elsif item_id_or_object.is_a?(String) # It's an ID string
      return all_items_map[item_id_or_object] if all_items_map&.key?(item_id_or_object)
      @logger.warn "Item ID string #{item_id_or_object} not found in pre-loaded map, fetching directly..."
      return @services_manager.inventory.get_item(item_id_or_object)
    end
    @logger.error "get_item_details_for_simulation: Could not determine item details from: #{item_id_or_object.inspect}"
    nil
  end

  # Helper to create a hash map of items by their ID
  def create_item_map(items_array)
    return {} unless items_array.is_a?(Array)
    items_array.each_with_object({}) do |item_obj, map|
      # Handle both direct item objects and StateManager entity objects
      item_id = item_obj['id'] || item_obj['clover_id'] || (item_obj['data'] && item_obj['data']['id'])
      map[item_id] = item_obj['data'] || item_obj if item_id
    end
  end

  # If `order.taxAmount` is available from Clover, that's preferred.
  def calculate_tax_amount(line_items_elements, all_tax_rates = []) # MODIFICATION: Added all_tax_rates parameter
    total_tax = 0
    return 0 unless line_items_elements && line_items_elements.is_a?(Array)

    # Fetch all default tax rates from the provided list
    # MODIFICATION: Use all_tax_rates parameter instead of @created_entities
    default_tax_rates_from_param = all_tax_rates.select { |tr| tr["isDefault"] == true }

    # Fallback to any "Sales Tax" if no explicit defaults found
    if default_tax_rates_from_param.empty?
      sales_tax = all_tax_rates.find { |tr| tr["name"]&.downcase == 'sales tax' && tr["rate"] }
      default_tax_rates_from_param << sales_tax if sales_tax
    end

    if default_tax_rates_from_param.empty?
        @logger.warn "No default tax rates found in provided list for tax calculation. Taxes may be $0.00."
    end

    line_items_elements.each do |line_item| # Iterate over elements if it's an array of line items
      # Safely access item details
      item_details = line_item["item"]
      next unless item_details && item_details["id"] # Skip if item details or ID are missing

      base_price = line_item["price"] || 0 # Price of the line item itself (already considers quantity if it's from order details)

      # Modifier prices are often included in the line item's price or handled by Clover's total calculation.
      # If modifiers need to be summed manually from line_item["modifications"]["elements"],
      # ensure that structure is present and sum their prices.
      # For now, assuming line_item["price"] is the price for the item *including* its selected modifiers *for its quantity*.
      # The API usually provides a calculated line item total.

      # If item_details contains its own "price", that's usually the unit price.
      # line_item["price"] from an order's line item is often the total for that line (unit_price * quantity + modifiers_for_that_item_instance)

      # Tax calculation should be based on the taxable amount of the line item.
      # If defaultTaxRates is true on the item, Clover applies them. If specific taxRates are on the line_item, those apply.

      taxable_amount_for_line_item = base_price # This is the total price for this line item (incl. quantity & mods)

      # Check for tax rates applied to this specific line item (if API provides this detail)
      # Or, check tax rates on the original item if line_item doesn't specify.
      tax_rates_to_apply = line_item["taxRates"]&.[]("elements") || item_details["taxRates"]&.[]("elements")

      if tax_rates_to_apply && tax_rates_to_apply.is_a?(Array)
        tax_rates_to_apply.each do |tax_rate_ref|
          # MODIFICATION: Use all_tax_rates parameter to find the tax rate by ID
          actual_rate_info = all_tax_rates.find { |tr| tr["id"] == tax_rate_ref["id"] }
          next unless actual_rate_info && actual_rate_info["rate"]

          rate_percentage = actual_rate_info["rate"].to_f / 10000.0 # Clover rates are in basis points (1/100 of a percent)
          total_tax += (taxable_amount_for_line_item * rate_percentage).round
        end
      elsif item_details["defaultTaxRates"] # If item uses default merchant tax rates
        # This logic is more complex as it requires knowing which of the merchant's tax rates apply by default.
        # The Clover API usually handles this server-side. Manually calculating default tax can be error-prone.
        # For accurate tax, it's best to rely on the order totals provided by Clover API after all line items are added.
        # This simulator's `calculate_tax_amount` is an estimation.
        # If `order.taxAmount` is available from Clover, that's preferred.
        @logger.warn "Item '#{item_details['name']}' uses defaultTaxRates. Manual tax calculation might be inexact here. Best to use total from API."
        # As a simplified fallback for default: apply the first 'General Tax' rate found, if any
        # MODIFICATION: Use the fetched default_tax_rates_from_param
        if default_tax_rates_from_param.any?
          default_tax_rates_from_param.each do |default_rate|
            rate_percentage = default_rate["rate"].to_f / 10000.0
            total_tax += (taxable_amount_for_line_item * rate_percentage).round
            @logger.info "Applied default tax rate '#{default_rate['name']}' (#{default_rate['rate']}) to line item amount #{taxable_amount_for_line_item}. Tax this item: #{(taxable_amount_for_line_item * rate_percentage).round}"
          end
        else # MODIFICATION: Corrected logger message
          @logger.warn "Item '#{item_details['name']}' uses defaultTaxRates, but no default rates found in provided list for calculation."
        end
      end
    end

    @logger.info "Calculated total_tax for order: #{total_tax}"
    total_tax
  end
end

# Parse command line arguments
options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: simulate_restaurant.rb [options]"

  opts.on("--generate-orders", "Generate past orders and payments after setup") do |g|
    options[:generate_orders] = g
  end

end.parse!

# Run the simulator
simulator = RestaurantSimulator.new
simulator.run(options)
