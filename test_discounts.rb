#!/usr/bin/env ruby
# test_discounts.rb - Tests discount creation with Clover API

# Add the local lib directory to the load path
$LOAD_PATH.unshift(File.expand_path("lib", __dir__))

require "clover_restaurant"
begin
  require "dotenv/load" # Load environment variables from .env file
rescue LoadError
  puts "dotenv gem not found, skipping .env file loading"
end

require "colorize"

# Configure Clover
CloverRestaurant.configure do |config|
  config.merchant_id = ENV["CLOVER_MERCHANT_ID"] || raise("Please set CLOVER_MERCHANT_ID in .env file")
  config.api_token = ENV["CLOVER_API_TOKEN"] || raise("Please set CLOVER_API_TOKEN in .env file")
  config.environment = ENV["CLOVER_ENVIRONMENT"] || "https://sandbox.dev.clover.com/"
  config.log_level = Logger::INFO
end

puts "\n#{"=" * 80}".colorize(:cyan)
puts "#{"DISCOUNT CREATION TEST".center(80)}".colorize(:cyan)
puts "#{"=" * 80}\n".colorize(:cyan)

# Get discount service
discount_service = CloverRestaurant::Services::DiscountService.new

# Step 1: Check existing discounts
puts "Checking existing discounts...".colorize(:light_blue)
discounts_response = discount_service.get_discounts
if discounts_response && discounts_response["elements"]
  existing_discounts = discounts_response["elements"]
  puts "Found #{existing_discounts.size} existing discounts"

  # Print the first few discounts
  existing_discounts.first(3).each do |discount|
    discount_type = discount["percentage"] ? "Percentage (#{discount["percentage"]}%)" : "Amount ($#{discount["amount"].abs / 100.0})"
    puts "  - #{discount["name"]} (#{discount_type})"
  end
else
  puts "No existing discounts found or error retrieving discounts"
  existing_discounts = []
end

# Step 2: Create test discounts
puts "\nCreating test discounts...".colorize(:light_blue)

test_discounts = [
  { "name" => "Test Percentage Discount", "percentage" => 15 },
  { "name" => "Test Amount Discount", "amount" => -500 }
]

created_discounts = []

test_discounts.each do |discount_data|
  # Skip if discount with same name already exists
  if existing_discounts.any? { |d| d["name"] == discount_data["name"] }
    puts "Discount '#{discount_data["name"]}' already exists, skipping.".colorize(:yellow)
    next
  end

  puts "Creating discount: #{discount_data.inspect}"
  response = discount_service.create_discount(discount_data)

  if response && response["id"]
    puts "✅ Successfully created discount: #{response["name"]} with ID: #{response["id"]}".colorize(:green)
    created_discounts << response
  else
    puts "❌ Error creating discount: #{response.inspect}".colorize(:red)
  end
end

if created_discounts.empty?
  puts "\nNo new discounts were created.".colorize(:yellow)
else
  puts "\nSuccessfully created #{created_discounts.size} discounts:".colorize(:green)
  created_discounts.each do |discount|
    discount_type = discount["percentage"] ? "Percentage (#{discount["percentage"]}%)" : "Amount ($#{discount["amount"].abs / 100.0})"
    puts "  - #{discount["name"]} (#{discount_type})"
  end
end

puts "\n#{"=" * 80}".colorize(:cyan)
puts "#{"TEST COMPLETED".center(80)}".colorize(:cyan)
puts "#{"=" * 80}\n".colorize(:cyan)
