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
  SETUP_STEPS = [
    'tax_rates',
    'categories',
    'modifier_groups',
    'menu_items',
    'roles',
    'employees',
    'shifts',
    'customers',
    'order_types'
  ]

  attr_reader :services_manager, :entity_generator, :logger

  def initialize
    @config = CloverRestaurant::Config.new
    @logger = @config.logger
    @state = CloverRestaurant::StateManager.new
    setup_services
  end

  def run(options = {})
    print_header

    if options[:reset]
      @logger.info "Resetting all state..."
      @state.reset_all
    end

    if options[:resume]
      @logger.info "Resuming from last successful step..."
    end

    begin
      setup_entities
      print_summary

      if options[:generate_orders]
        @logger.info "Proceeding to generate past orders and payments..."
        # Define default ranges or allow them to be configurable later
        # For now, using constants or direct values if they exist, otherwise defaults.
        # These might be DEFAULT_DAYS_RANGE and DEFAULT_ORDERS_PER_DAY if defined in the class
        # or we can use sensible defaults like 7 days, 5-15 orders/day.
        days_to_generate = options.fetch(:days_range, 7) # Default to 7 days
        orders_per_day = options.fetch(:orders_per_day, {min: 5, max: 15}) # Default to 5-15 orders

        # Convert orders_per_day to a range if it's a hash
        # Assuming generate_past_orders expects a range for orders_per_day_range
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

      # Save error state
      @state.mark_step_completed('last_error', {
        message: e.message,
        step: @current_step,
        time: Time.now.iso8601
      })

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
    @logger.info "Setting up Clover entities..."

    SETUP_STEPS.each do |step|
      @current_step = step

      if @state.step_completed?(step)
        @logger.info "Step '#{step}' already completed, skipping..."
        next
      end

      @logger.info "Step #{SETUP_STEPS.index(step) + 1}: Creating #{step.gsub('_', ' ')}..."

      begin
        case step
        when 'tax_rates'
          setup_tax_rates
        when 'categories'
          setup_categories
        when 'modifier_groups'
          setup_modifier_groups
        when 'menu_items'
          setup_menu_items
        when 'roles'
          setup_roles
        when 'employees'
          setup_employees
        when 'shifts'
          setup_shifts
        when 'customers'
          setup_customers
        when 'order_types'
          setup_order_types
        end

        @state.mark_step_completed(step)
        @logger.info "✅ Successfully completed step: #{step}"
      rescue StandardError => e
        @logger.error "❌ Failed to complete step '#{step}': #{e.message}"
        raise
      end
    end
  end

  def setup_tax_rates
    return if @state.step_completed?('tax_rates')

    # First check existing tax rates
    existing_rates = @services_manager.tax.get_tax_rates
    if existing_rates && existing_rates["elements"]&.any?
      @logger.info "Found #{existing_rates["elements"].size} existing tax rates"
      existing_rates["elements"].each do |rate|
        @state.record_entity('tax_rate', rate["id"], rate["name"], rate)
      end
      return
    end

    rates = @services_manager.tax.create_standard_tax_rates
    rates.each do |rate|
      @state.record_entity('tax_rate', rate["id"], rate["name"], rate)
    end
  end

  def setup_categories
    return if @state.step_completed?('categories')

    # Check existing categories
    existing_categories = @services_manager.inventory.get_categories
    if existing_categories && existing_categories["elements"]&.any?
      @logger.info "Found #{existing_categories["elements"].size} existing categories"
      existing_categories["elements"].each do |category|
        @state.record_entity('category', category["id"], category["name"], category)
      end
      return
    end

    categories = @services_manager.inventory.create_standard_categories
    categories.each do |category|
      @state.record_entity('category', category["id"], category["name"], category)
    end
  end

  def setup_modifier_groups
    return if @state.step_completed?('modifier_groups')

    # Check existing modifier groups
    existing_groups = @services_manager.inventory.get_modifier_groups
    if existing_groups && existing_groups["elements"]&.any?
      @logger.info "Found #{existing_groups["elements"].size} existing modifier groups"
      existing_groups["elements"].each do |group|
        @state.record_entity('modifier_group', group["id"], group["name"], group)
      end
      return
    end

    groups = @services_manager.inventory.create_standard_modifier_groups
    groups.each do |group|
      @state.record_entity('modifier_group', group["id"], group["name"], group)
    end
  end

  def setup_menu_items
    return if @state.step_completed?('menu_items')

    categories = @state.get_entities('category')
    modifier_groups = @state.get_entities('modifier_group')

    items = @services_manager.inventory.create_sample_menu_items(categories)
    items.each do |item|
      @state.record_entity('menu_item', item["id"], item["name"], item)
    end
  end

  def setup_roles
    return if @state.step_completed?('roles')

    # Check existing roles
    existing_roles = @services_manager.employee.get_roles
    if existing_roles && existing_roles["elements"]&.any?
      @logger.info "Found #{existing_roles["elements"].size} existing roles"
      existing_roles["elements"].each do |role|
        @state.record_entity('role', role["id"], role["name"], role)
      end
      return
    end

    roles = @services_manager.employee.create_standard_restaurant_roles
    roles.each do |role|
      @state.record_entity('role', role["id"], role["name"], role)
    end
  end

  def setup_employees
    return if @state.step_completed?('employees')

    roles = @state.get_entities('role')
    employees = @services_manager.employee.create_random_employees(15, roles)
    employees.each do |employee|
      @state.record_entity('employee', employee["id"], employee["name"], employee)
    end
  end

  def setup_shifts
    return if @state.step_completed?('shifts')

    employees = @state.get_entities('employee')
    employees.each do |employee|
      shift = @services_manager.employee.clock_in(employee["clover_id"])
      @state.record_entity('shift', shift["id"], "#{employee["name"]}_shift", shift) if shift
    end
  end

  def setup_customers
    return if @state.step_completed?('customers')

    # Check existing customers first (optional, but good practice if API supports efficient lookup)
    # For this example, we'll just create new ones if the step isn't completed.
    # If you wanted to check, you might do something like:
    # existing_customers = @services_manager.customer.get_customers
    # if existing_customers && existing_customers["elements"]&.any?
    #   @logger.info "Found #{existing_customers["elements"].size} existing customers"
    #   existing_customers["elements"].each do |cust|
    #     @state.record_entity('customer', cust["id"], cust["firstName"] ? "#{cust["firstName"]} #{cust["lastName"]}" : "Customer #{cust["id"]}", cust)
    #   end
    #   return
    # end

    customers = @services_manager.customer.create_random_customers(30) # Create 30 random customers
    customers.each do |customer|
      if customer && customer["id"]
        # Determine a display name for the customer
        display_name = if customer["firstName"] && customer["lastName"]
                         "#{customer["firstName"]} #{customer["lastName"]}"
                       elsif customer["firstName"]
                         customer["firstName"]
                       elsif customer["emailAddresses"]&.first&.[]("emailAddress")
                         customer["emailAddresses"].first["emailAddress"]
                       else
                         "Customer #{customer["id"]}"
                       end
        @state.record_entity('customer', customer["id"], display_name, customer)
      else
        @logger.warn "Failed to create or retrieve ID for a customer: #{customer.inspect}"
      end
    end
  end

  def setup_order_types
    return if @state.step_completed?('order_types')

    existing_order_types_response = @services_manager.merchant.get_order_types
    if existing_order_types_response && existing_order_types_response["elements"]&.any?
      @logger.info "Found #{existing_order_types_response["elements"].size} existing order types."
      existing_order_types_response["elements"].each do |ot|
        @state.record_entity('order_type', ot["id"], ot["label"] || ot["name"], ot)
      end
      return # Assuming existing ones are sufficient
    end

    @logger.info "No existing order types found or error fetching. Creating default order types."
    default_order_types = [
      { name: "Dine In", label: "Dine In", taxable: true, isDefault: true },
      { name: "Take Out", label: "Take Out", taxable: true, isDefault: false },
      { name: "Delivery", label: "Delivery", taxable: true, isDefault: false }
    ]

    default_order_types.each do |ot_data|
      begin
        created_ot = @services_manager.merchant.create_order_type(ot_data)
        if created_ot && created_ot["id"]
          @logger.info "✅ Successfully created order type: #{created_ot["label"]}"
          @state.record_entity('order_type', created_ot["id"], created_ot["label"], created_ot)
        else
          @logger.error "❌ Failed to create order type: #{ot_data[:label]}. Response: #{created_ot.inspect}"
        end
      rescue StandardError => e
        @logger.error "❌ Error creating order type #{ot_data[:label]}: #{e.message}"
      end
    end
  end

  def print_summary
    summary = @state.get_creation_summary

    table = Terminal::Table.new do |t|
      t.title = "Setup Summary"
      t.headings = ['Entity Type', 'Count']

      summary.each do |type, count|
        t.add_row [type, count]
      end
    end

    puts "\n" + table.to_s + "\n"
  end

  #
  # Order Generation Methods
  #

  def generate_past_orders(days_range = DEFAULT_DAYS_RANGE, orders_per_day_range = DEFAULT_ORDERS_PER_DAY)
    logger.info "Generating orders for the past #{days_range} days..."

    # --- DEBUG: Force 1 day, 1 order ---
    days_to_generate = 1 # Override for debugging
    orders_per_day_override = 1 # Override for debugging
    logger.info "[DEBUG] Overriding to generate 1 order for 1 day."
    # --- END DEBUG ---

    # Load all required data upfront
    resources = load_all_resources
    validate_resources(resources)

    successful_orders = []

    # Create orders for each day in the range
    (1..days_to_generate).each do |days_ago| # MODIFIED to use days_to_generate
      past_date = Time.now - days_ago.days
      date_string = past_date.strftime("%Y-%m-%d")

      # Vary number of orders by day of week - overridden for debug
      # base_orders = case past_date.wday
      #              when 5, 6 # Friday and Saturday
      #                rand(15..25) # Busy weekend
      #              when 0 # Sunday
      #                rand(10..15) # Busy brunch
      #              when 1..4 # Monday to Thursday
      #                rand(5..10) # Regular weekday
      #              end
      base_orders = orders_per_day_override # MODIFIED for debug

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
      items: fetch_with_rescue { @state.get_entities('menu_item') },
      categories: fetch_with_rescue { @services_manager.inventory.get_categories["elements"] },
      customers: fetch_with_rescue { @state.get_entities('customer') },
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
    orders_for_this_batch = [] # Changed variable name

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
    num_items = rand(1..3) # Random number of items per order

    num_items.times do
      # Randomly select a list of items from a category
      items_in_category = category_map.values.sample # items_in_category is an array of items
      next unless items_in_category && !items_in_category.empty? # MODIFIED: Ensure it's not nil and not empty

      # Randomly select an item from that list
      item = items_in_category.sample # MODIFIED: Sample directly from items_in_category
      next unless item # Ensure item is not nil

      # Get modifiers for this item
      # Use item["clover_id"] as items from StateManager store the Clover ID there.
      item_actual_id = item["clover_id"] || item["id"] # Fallback to item["id"] just in case
      unless item_actual_id && !item_actual_id.empty?
        logger.warn "Skipping modifier fetch for item because its ID is missing or empty: #{item.inspect}"
        modifiers = []
      else
        modifiers = get_item_modifiers(item_actual_id)
      end
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
    order_type_to_use = @state.get_entities('order_type').sample
    unless order_type_to_use && order_type_to_use["clover_id"]
      @logger.error "No order types available in state. Cannot create order."
      return false # Or raise an error
    end

    order_data = {
      "state" => "open",
      "createdTime" => timestamp,
      "modifiedTime" => timestamp,
      "orderType" => {
        "id" => order_type_to_use["clover_id"]
      }
    }

    # Add employee if available
    if resources[:employees] && !resources[:employees].empty?
      order_data["employee"] = { "id" => resources[:employees].sample["id"] }
    end

    # Add customer if available
    if resources[:customers] && !resources[:customers].empty?
      order_data["customer"] = { "id" => resources[:customers].sample["id"] }
    end

    # Prepare line_items for OrderService
    prepared_line_items = line_items.map do |li|
      item_obj = li[:item]
      actual_item_id = item_obj["clover_id"] || item_obj["id"]

      {
        :item_id => actual_item_id,
        :quantity => li[:quantity],
        :modifications => (li[:modifiers] || []).map do |mod|
          {
            "modifier" => { "id" => mod[:id] },
            "name" => mod[:name],
            "amount" => mod[:price]
          }
        end
        # :notes => nil # if you have notes
      }
    end
    order_data["line_items"] = prepared_line_items

    # Create the order (OrderService#create_order will now handle adding these line items)
    order = @services_manager.order.create_order(order_data)
    return false unless order && order["id"]

    # Step 2: Add line items with modifiers -- THIS SECTION IS NOW HANDLED BY OrderService#create_order
    # line_items.each do |line_item|
    #   item = line_item[:item]
    #   quantity = line_item[:quantity]
    #   modifiers = line_item[:modifiers]

    #   line_item_data = {
    #     "item" => { "id" => item["id"] },
    #     "name" => item["name"],
    #     "price" => item["price"],
    #     "printed" => false,
    #     "quantity" => quantity
    #   }

    #   # Add modifiers if present
    #   if modifiers && !modifiers.empty?
    #     line_item_data["modifications"] = modifiers.map do |mod|
    #       {
    #         "modifier" => { "id" => mod[:id] },
    #         "name" => mod[:name],
    #         "price" => mod[:price]
    #       }
    #     end
    #   end

    #   # Create the line item
    #   @services_manager.order.create_line_item(order["id"], line_item_data)
    # end

    # Step 3: Calculate totals (This is now done within OrderService#create_order or needs re-evaluation)
    # For now, assume OrderService#create_order returns an order object with total, or we fetch it.
    # Let's simplify and assume `order` returned from `create_order` might have totals, or we fetch them.
    # The `total` variable used for payment should be based on the final order state.

    # Fetch the fresh order details, especially if totals are calculated server-side after line items.
    current_order_details = @services_manager.order.get_order(order["id"])
    return false unless current_order_details

    total_from_order = current_order_details["total"] || 0 # Get total from the order object

    # Step 4: Apply discount if present
    if discount
      discount_amount = calculate_discount_amount(discount, total_from_order) # Calculate discount on the actual subtotal/total
      if discount_amount > 0
        @logger.info "Attempting to apply discount ID '#{discount["id"]}' of #{discount_amount} to order '#{order["id"]}'"
        applied_discount_line = @services_manager.order.apply_discount(order["id"], discount["id"], discount_amount)
        if applied_discount_line && applied_discount_line["id"]
          # If discount application affects total, Clover API often returns the updated order or discount line.
          # We might need to re-fetch order or adjust total_after_discount based on response.
          # For now, assume Clover recalculates or the payment step will use the order total from Clover.
          @logger.info "Successfully applied discount. Recalculating total or relying on order's current total for payment."
          # Re-fetch order to get the most up-to-date total after discount application
          updated_order_details = @services_manager.order.get_order(order["id"])
          total_after_discount = updated_order_details["total"] || total_from_order - discount_amount if updated_order_details
        else
          @logger.warn "Failed to apply discount or no confirmation of discount effect on total. Using pre-discount total for payment or manual adjustment."
          total_after_discount = total_from_order # Fallback or keep as is if apply_discount failed
        end
      else
        total_after_discount = total_from_order
      end
    else
      total_after_discount = total_from_order
    end

    # DEBUG LOGGING START
    logger.info "DEBUG: Before payment block for Order ID #{current_order_details['id']}:"
    logger.info "  total_from_order: #{total_from_order}"
    logger.info "  discount_amount (if discount applied): #{discount_amount || 'N/A'}"
    logger.info "  total_after_discount: #{total_after_discount}"
    # DEBUG LOGGING END

    # Step 5: Process payment
    if total_after_discount > 0 # Use total_after_discount for payment
      # Select a tender (prefer non-card tenders in sandbox)
      # Ensure tenders are available
      tender = resources[:tenders].find { |t| !t["label"].downcase.include?("card") } || resources[:tenders].first
      unless tender
        @logger.error "No suitable tender found for payment. Order: #{current_order_details['id']}"
        # Update order with a note about payment failure due to no tender
        @services_manager.order.update_order(current_order_details["id"], { "note" => "Payment failed: No suitable tender." })
        return order # Return order even if payment fails, summary will show pending
      end

      # Define employee_id_for_payment (ensure this is defined before use)
      employee_id_for_payment = current_order_details.dig("employee", "id") || resources[:employees]&.sample&.[]("id")
      unless employee_id_for_payment
         @logger.warn "No employee ID found for payment on order #{current_order_details['id']}. Payment might fail or use a default."
         # Fallback if truly no employee can be found (should be rare if setup is complete)
         employee_id_for_payment = @state.get_entities('employee')&.sample&.[]("id")
      end

      tip_percentage = rand(15..25) # Tip between 15% and 25%
      tip_amount_for_payment_service = ((total_after_discount * tip_percentage) / 100.0).round
      tip_amount_for_payment_service = [0, tip_amount_for_payment_service].max # Ensure tip is not negative

      # tax_amount_for_payment_service is now correctly calculated by the updated calculate_tax_amount
      tax_amount_for_payment_service = calculate_tax_amount(current_order_details["lineItems"]&.[]("elements"))

      total_for_payment_service = total_after_discount + tip_amount_for_payment_service # This is subtotal + tip for PaymentService

      # DEBUG LOGGING START (Ensure this is before the call)
      logger.info "DEBUG: Values for PaymentService call on Order ID #{current_order_details['id']}:"
      logger.info "  total_after_discount (subtotal used for tip/tax calcs): #{total_after_discount}"
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
        return order # Return order, summary will show payment as pending/failed
      end
      payment_id = payment_response["id"]
      paid_amount = payment_response["amount"] # This is the subtotal part of the payment

      # Update order state to paid
      @services_manager.order.update_order(current_order_details["id"], { "state" => "paid", "paymentState" => "PAID" })
      #MODIFICATION: Add payment details to the order object for summary
      order["payment_status"] = "Paid"
      order["tender_label"] = tender["label"] # Use the fetched tender's label
      order["payment_id"] = payment_id
      order["tip_amount"] = tip_amount_for_payment_service # Log tip
      order["tax_amount"] = tax_amount_for_payment_service # Log tax

      # Simulate a partial refund (e.g., 5% chance)
      if rand < 0.05 && paid_amount > 0 # Ensure there's something to refund
        refund_amount = (paid_amount * rand(0.1..0.5)).round # Refund 10-50% of the payment subtotal
        if refund_amount > 0
          @logger.info "Attempting to issue a partial refund of $#{refund_amount / 100.0} for payment '#{payment_id}' on order '#{current_order_details['id']}'."
          @services_manager.payment.create_refund(payment_id, current_order_details["id"], refund_amount)
        end
      end

    else # total_after_discount <= 0
      @logger.warn "Total amount for order '#{current_order_details['id']}' is not positive (#{total_after_discount}), skipping payment."
      # Update order with a note about no payment processed
      @services_manager.order.update_order(current_order_details["id"], { "note" => "No payment processed: Total was not positive." })
      #MODIFICATION: Add payment status to the order object for summary
      order["payment_status"] = "NoPayment (ZeroTotal)"
      order["tip_amount"] = 0 # No tip if no payment
      order["tax_amount"] = 0 # No tax if no payment

    end

    #MODIFICATION: If order was returned (even if payment failed), update its attributes from current_order_details
    if order && current_order_details
      order["total"] = current_order_details["total"] || 0 # Ensure total is from the definitive source
      order["original_total_from_order_service"] = total_from_order # Keep track of this for debugging
    end

    order # Return the original order object, potentially modified with payment status
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

  def get_item_modifiers(item_id)
    # Use the InventoryService to get modifier groups and their modifiers for the item
    # Ensure item_id is not nil or empty before making the API call
    return [] if item_id.nil? || item_id.empty?
    @services_manager.inventory.get_modifier_groups_for_item(item_id)
  end

  def calculate_tax_amount(line_items_elements) # Expecting the 'elements' array
    total_tax = 0
    return 0 unless line_items_elements && line_items_elements.is_a?(Array)

    line_items_elements.each do |line_item| # Iterate over elements if it's an array of line items
      # Assuming line_item structure is like: { "item" => {...}, "price" => ..., "modifications" => { "elements" => [...] } }
      # or directly the line item hash if not wrapped further.
      # The structure from current_order_details["lineItems"]["elements"] should be an array of line item objects.

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
          # tax_rate_ref might be just { "id": "..." } or could contain the rate.
          # If it's just an ID, you might need to fetch the full tax rate details.
          # For simplicity, let's assume `tax_rate_ref` directly has the 'rate' if it's populated by an expand query.
          # Otherwise, one would fetch @services_manager.tax.get_tax_rate_details(tax_rate_ref["id"])
          # For the demo, we'll assume 'rate' is present if tax_rates_to_apply exists.

          actual_rate_info = @state.get_entity_by_id('tax_rate', tax_rate_ref["id"]) # Fetch from state by ID
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
        general_tax_rate = @state.get_entities('tax_rate').find { |tr| tr["name"].downcase.include?('general') && tr["rate"] }
        if general_tax_rate
          rate_percentage = general_tax_rate["rate"].to_f / 10000.0
          total_tax += (taxable_amount_for_line_item * rate_percentage).round
        end
      end
    end

    total_tax
  end
end

# Parse command line arguments
options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: simulate_restaurant.rb [options]"

  opts.on("--reset", "Reset all existing data before running") do |r|
    options[:reset] = r
  end

  opts.on("--resume", "Resume from the last successful step") do |r|
    options[:resume] = r
  end

  opts.on("--generate-orders", "Generate past orders and payments after setup") do |g|
    options[:generate_orders] = g
  end

  # Potentially add options for days_range and orders_per_day here if desired
  # opts.on("--days-range DAYS", Integer, "Number of past days to generate orders for") do |days|
  #   options[:days_range] = days
  # end

end.parse!

# Run the simulator
simulator = RestaurantSimulator.new
simulator.run(options)
