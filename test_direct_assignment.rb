#!/usr/bin/env ruby
# direct_assignment_test.rb - Tests direct item-to-category assignment

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
puts "#{"DIRECT CATEGORY ASSIGNMENT TEST".center(80)}".colorize(:cyan)
puts "#{"=" * 80}\n".colorize(:cyan)

# Get services
inventory_service = CloverRestaurant::Services::InventoryService.new

# Define direct assignment method
def direct_assign_item_to_category(inventory_service, item, category)
  puts "Attempting to assign item #{item} to category #{category}..."
  puts "Item: #{item.inspect}"
  puts "Category: #{category.inspect}"

  # Create the payload for assignment
  payload = {
    "elements" => [
      {
        "category" => { "id" => category["id"] },
        "item" => { "id" => item["id"] }
      }
    ]
  }

  # Make the API request
  endpoint = "category_items?expand=items"
  puts "Sending request to endpoint: #{endpoint}..."
  puts "Payload: #{payload.inspect}"
  response = inventory_service.send(:make_request, :post, inventory_service.send(:endpoint, endpoint), payload)
  puts "Response: #{response.inspect}"
  if response
    puts "✅ Assignment successful!".colorize(:green)
    true
  else
    puts "❌ Assignment failed!".colorize(:red)
    puts "Response: #{response.inspect}"
    false
  end
end

# Step 1: Fetch categories
puts "Fetching all categories...".colorize(:light_blue)
categories_response = inventory_service.get_categories
categories = categories_response && categories_response["elements"] ? categories_response["elements"] : []

if categories.empty?
  puts "No categories found. Exiting.".colorize(:red)
  exit 1
end

# Print available categories
puts "\nAvailable Categories:".colorize(:yellow)
categories.each_with_index do |category, index|
  puts "#{index + 1}. #{category["name"]} (ID: #{category["id"]})"
end

# Step 2: Fetch items
puts "\nFetching all items...".colorize(:light_blue)
items_response = inventory_service.get_items
items = items_response && items_response["elements"] ? items_response["elements"] : []

if items.empty?
  puts "No items found. Exiting.".colorize(:red)
  exit 1
end

# Print available items
puts "\nAvailable Items:".colorize(:yellow)
items.each_with_index do |item, index|
  puts "#{index + 1}. #{item["name"]} (ID: #{item["id"]})"

  # Print category info
  if item["categories"]
    if item["categories"].is_a?(Hash) && item["categories"]["elements"]
      categories_count = item["categories"]["elements"].size
      category_names = item["categories"]["elements"].map { |c| c["name"] }.join(", ")
      if categories_count > 0
        puts "   Has #{categories_count} categories: #{category_names}"
      else
        puts "   Has 0 categories (empty elements array)"
      end
    elsif item["categories"].is_a?(Array)
      categories_count = item["categories"].size
      category_names = item["categories"].map { |c| c["name"] }.join(", ")
      if categories_count > 0
        puts "   Has #{categories_count} categories: #{category_names}"
      else
        puts "   Has 0 categories (empty array)"
      end
    else
      puts "   Categories info: #{item["categories"].inspect}"
    end
  else
    puts "   No categories information"
  end
end

# Step 3: Select some items and a category for testing
puts "\nSelecting items and category for test assignment...".colorize(:light_blue)

# Select a category (using the first one for this test)
selected_category = categories.first
puts "Selected category: #{selected_category["name"]} (ID: #{selected_category["id"]})".colorize(:green)

# Select a few items (first 3 for this test)
selected_items = items
puts "Selected items:".colorize(:green)
selected_items.each do |item|
  puts "  - #{item["name"]} (ID: #{item["id"]})"
end

# Step 4: Perform direct assignments
puts "\nPerforming direct assignments...".colorize(:light_blue)
results = []

selected_items.each do |item|
  result = direct_assign_item_to_category(inventory_service, item, categories.sample)
  results << {
    item_name: item["name"],
    item_id: item["id"],
    success: result
  }
end

# Step 5: Verify the assignments
puts "\nVerifying assignments...".colorize(:light_blue)
selected_items.each do |item|
  puts "Checking categories for #{item["name"]} (ID: #{item["id"]})..."

  # Get updated item data
  updated_item = inventory_service.get_item(item["id"])

  # Check if the item now has the category
  has_category = false
  category_found = false

  if updated_item["categories"]
    if updated_item["categories"].is_a?(Hash) && updated_item["categories"]["elements"]
      categories_count = updated_item["categories"]["elements"].size
      has_category = categories_count > 0

      if has_category
        category_found = updated_item["categories"]["elements"].any? do |c|
          c["id"] == selected_category["id"]
        end
      end
    elsif updated_item["categories"].is_a?(Array)
      categories_count = updated_item["categories"].size
      has_category = categories_count > 0

      if has_category
        category_found = updated_item["categories"].any? do |c|
          c["id"] == selected_category["id"]
        end
      end
    end
  end

  if category_found
    puts "✅ Verification successful! Item now has the category.".colorize(:green)
  else
    puts "❌ Verification failed! Item does not have the category.".colorize(:red)
    puts "Updated item data: #{updated_item.inspect}"
  end
end

puts "\n#{"=" * 80}".colorize(:cyan)
puts "#{"TEST COMPLETED".center(80)}".colorize(:cyan)
puts "#{"=" * 80}\n".colorize(:cyan)
