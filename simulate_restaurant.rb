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
  attr_reader :services_manager, :entity_generator

  def initialize
    configure_clover
    @services_manager = CloverRestaurant::CloverServicesManager.new
    @entity_generator = CloverRestaurant::DataGeneration::EntityGenerator.new(@services_manager.config,
                                                                              @services_manager)
  end

  def run
    display_header
    setup_entities
    generate_past_orders
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
    @entity_generator.create_entities
    @services_manager.tender.create_standard_tenders
    puts "✅ Clover setup complete."
  end

  def generate_past_orders(order_count = 5)
    puts "\n💳 Generating orders and payments for the past 30 days...".colorize(:light_blue)

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
    discounts = begin
      @services_manager.discount.get_discounts["elements"]
    rescue StandardError
      []
    end

    return puts "❌ No items available to create orders!" if items.empty?
    return puts "❌ No employees available!" if employees.empty?
    return puts "❌ No customers available!" if customers.empty?

    (4..30).each do |days_ago|
      past_date = Time.now - days_ago.days
      random_hour = rand(7..22) # Random hour between 7 AM and 10 PM
      random_minute = rand(0..59)
      random_second = rand(0..59)

      # Create a Time object for the past date and random time
      past_time = Time.new(past_date.year, past_date.month, past_date.day, random_hour, random_minute, random_second)

      # Convert to milliseconds since Unix epoch
      past_timestamp = (past_time.to_f * 1000).to_i

      order_count.times do
        employee = employees.sample
        customer = customers.sample

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

        # Add line items to the order
        selected_items.each do |item|
          quantity = rand(1..2)
          total_price += (item["price"] || 0) * quantity
          @services_manager.order.add_line_item(order_id, item["id"], quantity)
          logger.info "Added item #{item["id"]} with price #{item["price"]} and quantity #{quantity}"
        end

        # Apply discount (if applicable)
        if rand < 0.4 && !discounts.empty?
          discount = discounts.sample
          @services_manager.order.apply_discount(order_id, discount["id"])
          logger.info "Applied discount #{discount["id"]} to order #{order_id}"
        end

        # Calculate and update the order total
        total = @services_manager.order.calculate_order_total(order_id)
        logger.info "Calculated total for order #{order_id}: #{total}"

        # Update the order total
        @services_manager.order.update_order_total(order_id, total)
        logger.info "Updated order #{order_id} total to #{total}"

        # Skip payment if the total is zero
        next if total.zero?

        # Update the order state to OPEN
        @services_manager.order.update_order_state(order_id, "OPEN")

        # Process payment
        payment_type = rand < 0.7 ? "CREDIT_CARD" : "CASH"

        if payment_type == "CREDIT_CARD"
          encryptor = CloverRestaurant::PaymentEncryptor.new(@services_manager)
          card_details = {
            card_number: "4111111111111111",
            exp_month: "12",
            exp_year: "2027",
            cvv: "123"
          }
          encrypted_payment = encryptor.prepare_payment_data(order_id, total, card_details)

          if encrypted_payment
            @services_manager.payment.process_payment(order_id, total, employee["id"], past_timestamp,
                                                      encrypted_payment)
          else
            puts "⚠️ Credit card encryption failed, using cash instead."
            @services_manager.payment.process_payment(order_id, total, employee["id"], past_timestamp)
          end
        else
          @services_manager.payment.process_payment(order_id, total, employee["id"], past_timestamp)
        end

        puts "✅ Order #{order_id} completed successfully for #{past_date.strftime("%Y-%m-%d")}!"
      end
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
