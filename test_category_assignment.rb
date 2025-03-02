#!/usr/bin/env ruby
# test_category_assignment.rb - Tests the item-to-category assignment functionality

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
puts "#{"CATEGORY ASSIGNMENT TEST".center(80)}".colorize(:cyan)
puts "#{"=" * 80}\n".colorize(:cyan)

# Get inventory service
inventory_service = CloverRestaurant::Services::InventoryService.new

# Step 1: Get all categories
puts "Fetching categories...".colorize(:light_blue)
categories_response = inventory_service.get_categories
categories = categories_response && categories_response["elements"] ? categories_response["elements"] : []
puts "Found #{categories.size} categories"

# If no categories, create default ones
if categories.empty?
  puts "\nNo categories found. Creating default categories...".colorize(:yellow)

  default_categories = [
    { "name" => "Appetizers" },
    { "name" => "Entrees" },
    { "name" => "Sides" },
    { "name" => "Desserts" },
    { "name" => "Drinks" },
    { "name" => "Alcoholic Beverages" },
    { "name" => "Specials" }
  ]

  created_categories = []

  default_categories.each do |category_data|
    response = inventory_service.create_category(category_data)

    if response && response["id"]
      created_categories << response
      puts "✅ Created category: #{response["name"]} (ID: #{response["id"]})"
    else
      puts "❌ Failed to create category: #{category_data["name"]}"
    end
  end

  categories = created_categories
end

# Step 2: Get all items
puts "\nFetching items...".colorize(:light_blue)
items_response = inventory_service.get_items
items = items_response && items_response["elements"] ? items_response["elements"] : []
puts "Found #{items.size} items"

# If no items, create sample ones
if items.empty? && !categories.empty?
  puts "\nNo items found. Creating sample menu items...".colorize(:yellow)

  created_items = inventory_service.create_sample_menu_items(categories)

  if created_items && !created_items.empty?
    puts "✅ Created #{created_items.size} sample menu items"
    items = created_items
  else
    puts "❌ Failed to create sample items"
  end
end

# Step 3: Check current category assignment status
puts "\nChecking current category assignments...".colorize(:light_blue)
total_assigned_items = 0

categories.each do |category|
  category_items = inventory_service.get_category_items(category["id"])
  count = category_items && category_items["elements"] ? category_items["elements"].size : 0
  total_assigned_items += count
  puts "  - #{category["name"]}: #{count} items"
end

puts "Total items with category assignments: #{total_assigned_items}"

# Step 4: Run auto-assignment if needed
if total_assigned_items < items.size
  unassigned_items = items.size - total_assigned_items
  puts "\nFound #{unassigned_items} items without category assignments.".colorize(:yellow)

  print "Do you want to run auto-assignment? (y/n): "
  response = gets.chomp.downcase

  if %w[y yes].include?(response)
    puts "\nRunning auto-assignment...".colorize(:light_blue)
    result = inventory_service.auto_assign_items_to_categories(items, categories)

    if result && result[:success]
      puts "✅ Successfully assigned #{result[:assigned_count]} items to categories"

      if result[:errors].any?
        puts "\nSome assignments had errors:".colorize(:yellow)
        result[:errors].first(5).each do |error|
          puts "  - #{error}"
        end
      end
    else
      puts "❌ Failed to assign items to categories".colorize(:red)
      if result && result[:errors]
        puts "Errors:".colorize(:red)
        result[:errors].first(5).each do |error|
          puts "  - #{error}"
        end
      end
    end

    # Verify results
    puts "\nVerifying results...".colorize(:light_blue)
    updated_total_assigned = 0

    categories.each do |category|
      category_items = inventory_service.get_category_items(category["id"])
      count = category_items && category_items["elements"] ? category_items["elements"].size : 0
      updated_total_assigned += count
      puts "  - #{category["name"]}: #{count} items"
    end

    puts "Updated total items with category assignments: #{updated_total_assigned}"
    puts "Improvement: #{updated_total_assigned - total_assigned_items} more items now have categories"
  else
    puts "Auto-assignment skipped."
  end
else
  puts "\n✅ All items already have category assignments".colorize(:green)
end

puts "\n#{"=" * 80}".colorize(:cyan)
puts "#{"TEST COMPLETED".center(80)}".colorize(:cyan)
puts "#{"=" * 80}\n".colorize(:cyan)
