#!/usr/bin/env ruby

require "clover_restaurant"

# Configure the gem
CloverRestaurant.configure do |config|
  config.merchant_id = "YOUR_MERCHANT_ID"
  config.api_key = "YOUR_API_KEY"
  config.environment = "https://sandbox.dev.clover.com/"
  config.log_level = Logger::INFO
end

# Create service instances
merchant_service = CloverRestaurant::MerchantService.new
# inventory_service = CloverRestaurant::InventoryService.new

# Get merchant info
begin
  merchant_info = merchant_service.get_merchant_info
  puts "Merchant Name: #{merchant_info["name"]}"
rescue StandardError => e
  puts "Error: #{e.message}"
end

# Create some sample inventory
begin
  inventory = inventory_service.create_random_restaurant_inventory(3, 5)
  puts "Created #{inventory[:categories].size} categories with #{inventory[:items].size} items"
rescue StandardError => e
  puts "Error: #{e.message}"
end
