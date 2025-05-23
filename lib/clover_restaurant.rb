# lib/clover_restaurant.rb
require "httparty"
require "json"
require "openssl"
require "base64"
require "logger"
require "faker"
require "active_support/time"
require 'rest-client'
require 'sqlite3'
require 'terminal-table'
require 'colorize'

# Base and core components
require_relative "clover_restaurant/version"
require_relative "clover_restaurant/errors"
require_relative "clover_restaurant/configuration"
require_relative "clover_restaurant/vcr_setup"
require_relative "clover_restaurant/base_service"
require_relative "clover_restaurant/payment_encryptor"
require_relative "clover_restaurant/clover_services_manager"
require_relative "clover_restaurant/state_manager"

# Services
require_relative "clover_restaurant/services/merchant_service"
require_relative "clover_restaurant/services/order_service"
require_relative "clover_restaurant/services/payment_service"
require_relative "clover_restaurant/services/tax_service"
require_relative "clover_restaurant/services/discount_service"
require_relative "clover_restaurant/services/employee_service"
require_relative "clover_restaurant/services/customer_service"
require_relative "clover_restaurant/services/menu_service"
require_relative "clover_restaurant/services/inventory_service"
require_relative "clover_restaurant/services/modifier_service"
require_relative "clover_restaurant/services/refund_service"
require_relative "clover_restaurant/services/tender_service"
require_relative "clover_restaurant/services/tip_service"
require_relative "clover_restaurant/services/device_service"

# Data Generation
require_relative "clover_restaurant/data_generation/delete_all"
require_relative "clover_restaurant/data_generation/base_generator"
require_relative "clover_restaurant/data_generation/daily_operation_generator"
require_relative "clover_restaurant/data_generation/entity_generator"
require_relative "clover_restaurant/data_generation/analytics_generator"

# Simulator
require_relative "clover_restaurant/simulator/base_simulator"
require_relative "clover_restaurant/simulator/entity_setup"
require_relative "clover_restaurant/simulator/restaurant_simulator"

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

  class Error < StandardError; end

  # Convenience method to create a new configuration
  def self.configure
    yield(config) if block_given?
    config
  end

  # Access the global configuration
  def self.config
    @config ||= Configuration.new
  end

  # Reset the configuration
  def self.reset_config!
    @config = Configuration.new
  end
end
