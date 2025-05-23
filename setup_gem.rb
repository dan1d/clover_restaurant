#!/usr/bin/env ruby
# setup_gem.rb - Script to set up the clover_restaurant gem structure

require 'fileutils'

# Set up directories
directories = [
  "lib/clover_restaurant",
  "lib/clover_restaurant/services"
]

directories.each do |dir|
  FileUtils.mkdir_p(dir) unless Dir.exist?(dir)
  puts "Created directory: #{dir}"
end

# Update gemspec
gemspec_content = File.read('clover_restaurant.gemspec')
updated_gemspec = gemspec_content.gsub(
  /spec\.summary\s+=.+$/,
  "spec.summary       = \"A Ruby gem for interacting with Clover API for restaurant operations\""
).gsub(
  /spec\.description\s+=.+$/,
  "spec.description   = \"Comprehensive interface for Clover API including orders, items, inventory, customers, payments, and more\""
)

# Add dependencies
unless gemspec_content.include?("spec.add_dependency \"httparty\"")
  dependency_section = "  spec.add_dependency \"httparty\", \"~> 0.18.1\"\n"
  dependency_section += "  spec.add_dependency \"json\", \"~> 2.3\"\n"
  dependency_section += "  spec.add_dependency \"faker\", \"~> 2.13\"\n"
  updated_gemspec = updated_gemspec.gsub(
    /(spec\.add_development_dependency.+$)/,
    "#{dependency_section}\n\\1"
  )
end

File.write('clover_restaurant.gemspec', updated_gemspec)
puts "Updated gemspec with dependencies"

# Create version.rb
version_content = <<~RUBY
  # lib/clover_restaurant/version.rb
  module CloverRestaurant
    VERSION = '0.1.0'.freeze
  end
RUBY

File.write('lib/clover_restaurant/version.rb', version_content)
puts "Created version.rb"

# Create main file
main_file_content = <<~RUBY
  # lib/clover_restaurant.rb
  require 'httparty'
  require 'json'
  require 'openssl'
  require 'base64'
  require 'logger'
  require 'faker'

  # Base and core components
  require_relative 'clover_restaurant/version'
  require_relative 'clover_restaurant/configuration'
  require_relative 'clover_restaurant/errors'
  require_relative 'clover_restaurant/base_service'
  require_relative 'clover_restaurant/payment_encryptor'

  # Services
  require_relative 'clover_restaurant/services/merchant_service'
  require_relative 'clover_restaurant/services/inventory_service'
  require_relative 'clover_restaurant/services/order_service'
  require_relative 'clover_restaurant/services/payment_service'
  require_relative 'clover_restaurant/services/employee_service'
  require_relative 'clover_restaurant/services/customer_service'
  require_relative 'clover_restaurant/services/modifier_service'
  require_relative 'clover_restaurant/services/discount_service'
  require_relative 'clover_restaurant/services/tip_service'
  require_relative 'clover_restaurant/services/refund_service'
  require_relative 'clover_restaurant/services/tax_rate_service'
  require_relative 'clover_restaurant/services/table_service'
  require_relative 'clover_restaurant/services/menu_service'
  require_relative 'clover_restaurant/services/reservation_service'

  module CloverRestaurant
    class << self
      attr_accessor :configuration

      def configure
        self.configuration ||= Configuration.new
        yield(configuration) if block_given?
      end

      def logger
        configuration.logger
      end
    end
  end
RUBY

File.write('lib/clover_restaurant.rb', main_file_content)
puts "Created main file"

# This script would continue with all other files...
puts "\nBase setup complete. You'll need to add the remaining files manually."
puts "Run 'bundle install' to install dependencies."
puts "Check the clover_restaurant directory structure to ensure all is in place."
