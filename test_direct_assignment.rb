#!/usr/bin/env ruby
# test_bulk_category_assignment.rb - Tests bulk item-to-category assignment

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
puts "#{"BULK CATEGORY ASSIGNMENT TEST".center(80)}".colorize(:cyan)
puts "#{"=" * 80}\n".colorize(:cyan)

# Get inventory service
inventory_service = CloverRestaurant::Services::InventoryService.new

# Step 1: Create test categories
puts "Creating test categories...".colorize(:light_blue)
test_categories = [
  { "name" => "Test Category 1 #{Time.now.to_i}" },
  { "name" => "Test Category 2 #{Time.now.to_i}" }
]

created_categories = []
test_categories.each do |category_data|
  response = inventory_service.create_category(category_data)
  if response && response["id"]
    created_categories << response
    puts "✅ Created category: #{response["name"]} (ID: #{response["id"]})"
  else
    puts "❌ Failed to create category: #{category_data["name"]}"
  end
end

if created_categories.empty?
  puts "❌ Could not create any test categories. Exiting.".colorize(:red)
  exit 1
end

# Step 2: Create test items
puts "\nCreating test items...".colorize(:light_blue)
test_items = [
  { "name" => "Test Item 1 #{Time.now.to_i}", "price" => 1099 },
  { "name" => "Test Item 2 #{Time.now.to_i}", "price" => 1599 },
  { "name" => "Test Item 3 #{Time.now.to_i}", "price" => 899 },
  { "name" => "Test Item 4 #{Time.now.to_i}", "price" => 1299 }
]

created_items = []
test_items.each do |item_data|
  response = inventory_service.create_item(item_data)
  if response && response["id"]
    created_items << response
    puts "✅ Created item: #{response["name"]} (ID: #{response["id"]})"
  else
    puts "❌ Failed to create item: #{item_data["name"]}"
  end
end

if created_items.empty?
  puts "❌ Could not create any test items. Exiting.".colorize(:red)
  exit 1
end

# Step 3: Create item-category mapping
puts "\nCreating item-category mapping...".colorize(:light_blue)
item_category_mapping = {}

# Assign the first two items to the first category
item_category_mapping[created_items[0]["id"]] = created_categories[0]["id"]
item_category_mapping[created_items[1]["id"]] = created_categories[0]["id"]

# Assign the next two items to the second category (if available)
if created_items.size >= 4 && created_categories.size >= 2
  item_category_mapping[created_items[2]["id"]] = created_categories[1]["id"]
  item_category_mapping[created_items[3]["id"]] = created_categories[1]["id"]
end

puts "Item-category mapping:"
item_category_mapping.each do |item_id, category_id|
  item_name = created_items.find { |i| i["id"] == item_id }["name"]
  category_name = created_categories.find { |c| c["id"] == category_id }["name"]
  puts "  - #{item_name} (#{item_id}) => #{category_name} (#{category_id})"
end

# Step 4: Perform bulk assignment
puts "\nPerforming bulk assignment...".colorize(:light_blue)

begin
  result = inventory_service.bulk_assign_items_to_categories(item_category_mapping)

  if result && result[:success]
    puts "✅ Bulk assignment succeeded: #{result[:updated_count]} items updated".colorize(:green)
  else
    puts "❌ Bulk assignment failed".colorize(:red)
    if result && result[:errors] && result[:errors].any?
      puts "Errors:"
      result[:errors].each do |error|
        puts "  - #{error}"
      end
    end
  end
rescue StandardError => e
  puts "❌ Error during bulk assignment: #{e.message}".colorize(:red)
  puts e.backtrace.join("\n") if ENV["DEBUG"]
end

# Step 5: Verify assignments
puts "\nVerifying assignments...".colorize(:light_blue)

# Check each category for its items
created_categories.each do |category|
  puts "Checking items in category: #{category["name"]} (#{category["id"]})"

  begin
    response = inventory_service.get_category_items(category["id"])
    items = response && response["elements"] ? response["elements"] : []

    if items.any?
      puts "Found #{items.size} items in category:"
      items.each do |item|
        puts "  - #{item["name"]} (#{item["id"]})"
      end
    else
      puts "No items found in category"
    end
  rescue StandardError => e
    puts "Error checking category items: #{e.message}"
  end
end

# Check each item for its categories
puts "\nChecking item categories..."
created_items.each do |item|
  puts "Checking categories for item: #{item["name"]} (#{item["id"]})"

  begin
    item_detail = inventory_service.get_item(item["id"])

    if item_detail && item_detail["categories"] && item_detail["categories"].any?
      puts "Item has #{item_detail["categories"].size} categories:"
      item_detail["categories"].each do |category|
        puts "  - #{category["name"]} (#{category["id"]})"
      end
    else
      puts "No categories found for item"
    end
  rescue StandardError => e
    puts "Error checking item categories: #{e.message}"
  end
end

puts "\n#{"=" * 80}".colorize(:cyan)
puts "#{"TEST COMPLETED".center(80)}".colorize(:cyan)
puts "#{"=" * 80}\n".colorize(:cyan)
