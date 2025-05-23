#!/usr/bin/env ruby

require 'clover_restaurant'
require 'dotenv'

# Load environment variables
Dotenv.load

# Configure the gem
CloverRestaurant.configure do |config|
  config.api_key = ENV['CLOVER_API_KEY']
  config.merchant_id = ENV['CLOVER_MERCHANT_ID']
  config.sandbox = ENV['CLOVER_SANDBOX'] == 'true'
  config.logger = Logger.new(STDOUT)
end

# Create a simulator instance
simulator = CloverRestaurant::Simulator::RestaurantSimulator.new

# Test different operations
puts "\nTesting different operations:"

puts "\n1. Testing help command:"
system('clover-restaurant --help')

puts "\n2. Testing status (should show no entities):"
simulator.print_summary rescue puts "No entities yet"

puts "\n3. Testing setup with reset:"
system('clover-restaurant --reset')

puts "\n4. Testing status after setup:"
simulator.print_summary rescue puts "Setup might have failed"

puts "\nTest completed!"
