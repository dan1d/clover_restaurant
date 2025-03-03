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

class CloverAutomation
  attr_reader :services_manager, :entity_generator, :logger

  def initialize
    configure_clover
    @services_manager = CloverRestaurant::CloverServicesManager.new
    @entity_generator = CloverRestaurant::DataGeneration::EntityGenerator.new(@services_manager.config,
                                                                              @services_manager)
    # Initialize the logger
    @logger = Logger.new($stdout)
    @logger.level = Logger::INFO
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
    puts "#{"CLOVER AUTOMATION".center(80)}".colorize(:cyan)
    puts "#{"=" * 80}\n".colorize(:cyan)

    puts "Merchant ID: #{ENV["CLOVER_MERCHANT_ID"]}"
    puts "Environment: #{ENV["CLOVER_ENVIRONMENT"]}"
  end

  def setup_entities
    puts "\n🔄 Setting up Clover entities...".colorize(:light_blue)
    # @entity_generator.cleanup_entities
    @entity_generator.create_entities
    @services_manager.tender.create_standard_tenders
    puts "✅ Clover setup complete."
  end

  def generate_past_orders(days_range = 30)
    puts "\n💳 Generating 1 order per day for the past #{days_range} days...".colorize(:light_blue)

    items = begin
      @services_manager.inventory.get_items["elements"]
    rescue StandardError
      []
    end
    customers = begin
      @services_manager.customer.get_customers["elements"]
    rescue StandardError
      []
    end
    employees = begin
      @services_manager.employee.get_employees["elements"]
    rescue StandardError
      []
    end
    tenders = begin
      @services_manager.tender.get_tenders["elements"]
    rescue StandardError
      []
    end

    # Filter for external tenders only to avoid the credit card payment error
    external_tenders = tenders.select do |tender|
      tender["label"] != "Credit Card" &&
        tender["label"] != "Debit Card" &&
        !tender["labelKey"]&.include?("credit") &&
        !tender["labelKey"]&.include?("debit")
    end

    # If no external tenders found, create one
    if external_tenders.empty?
      puts "⚠️ No external tenders found. Creating a custom tender..."
      external_tender = @services_manager.tender.create_tender({
                                                                 "label" => "External Payment",
                                                                 "labelKey" => "com.clover.tender.external",
                                                                 "enabled" => true,
                                                                 "visible" => true,
                                                                 "opensCashDrawer" => false
                                                               })
      external_tenders = [external_tender] if external_tender
    end

    return puts "❌ No items available to create orders!" if items.empty?
    return puts "❌ No employees available!" if employees.empty?
    return puts "❌ No customers available!" if customers.empty?
    return puts "❌ No payment tenders available!" if external_tenders.empty?

    (1..days_range).each do |days_ago|
      past_date = Time.now - days_ago.days
      random_hour = rand(7..22) # Random hour between 7 AM and 10 PM
      random_minute = rand(0..59)
      random_second = rand(0..59)

      # Create a Time object for the past date and random time
      past_time = Time.new(past_date.year, past_date.month, past_date.day, random_hour, random_minute, random_second)

      # Convert to milliseconds since Unix epoch
      past_timestamp = (past_time.to_f * 1000).to_i

      employee = employees.sample
      customer = customers.sample
      tender = external_tenders.sample

      order_data = {
        "employee" => { "id" => employee["id"] },
        "customers" => [{ "id" => customer["id"] }],
        "diningOption" => %w[HERE TO_GO DELIVERY].sample,
        "createdTime" => past_timestamp,
        "clientCreatedTime" => past_timestamp
      }

      # Create the order
      order = @services_manager.order.create_order(order_data)
      next unless order && order["id"]

      order_id = order["id"]

      # Pre-calculate the total amount
      total_price = 0

      # Randomly select items for the order
      selected_items = items.sample(rand(1..5)) # Select 1 to 5 random items

      # Add line items to the order
      selected_items.each do |item|
        quantity = rand(1..2)
        item_price = item["price"] || 0
        total_price += item_price * quantity

        begin
          line_item = @services_manager.order.add_line_item(order_id, item["id"], quantity)
          puts "➕ Added item #{item["name"] || item["id"]} - $#{item_price / 100.0} x #{quantity}"
        rescue StandardError => e
          puts "⚠️ Failed to add item: #{e.message}"
        end
      end

      # Allow time for line items to be processed
      sleep(1)

      # Force the order total update
      @services_manager.order.update_order_total(order_id, total_price)
      puts "💰 Set order total to $#{total_price / 100.0}"

      # Skip payment if the total is zero
      if total_price.zero?
        puts "⚠️ Order #{order_id} has a total of 0. Skipping payment."
        next
      end

      # Update the order state to OPEN
      @services_manager.order.update_order_state(order_id, "OPEN")

      # Process payment with external tender
      payment_data = {
        "order" => { "id" => order_id },
        "tender" => { "id" => tender["id"] },
        "employee" => { "id" => employee["id"] },
        "amount" => total_price,
        "createdTime" => past_timestamp,
        "clientCreatedTime" => past_timestamp
      }

      begin
        payment = make_external_payment(order_id, payment_data)
        if payment && payment["id"]
          puts "✅ Order #{order_id} completed for #{past_date.strftime("%Y-%m-%d")} with payment #{payment["id"]}"
        else
          puts "⚠️ Payment processing failed for order #{order_id}"
        end
      rescue StandardError => e
        puts "⚠️ Error processing payment: #{e.message}"
      end
    end
  end

  # Helper method to make external payments directly
  def make_external_payment(order_id, payment_data)
    endpoint = "v3/merchants/#{@services_manager.config.merchant_id}/orders/#{order_id}/payments"
    headers = {
      "Authorization" => "Bearer #{@services_manager.config.api_token}",
      "Content-Type" => "application/json"
    }

    uri = URI.parse("#{@services_manager.config.environment.chomp("/")}/" + endpoint)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Post.new(uri.request_uri, headers)
    request.body = payment_data.to_json

    response = http.request(request)

    if response.code.to_i == 200
      JSON.parse(response.body)
    else
      puts "⚠️ Payment request failed: #{response.body}"
      nil
    end
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
