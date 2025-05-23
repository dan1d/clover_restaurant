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
require_relative "clover_restaurant/config"
require_relative "clover_restaurant/base_service"
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
require_relative "clover_restaurant/services/inventory_service"
require_relative "clover_restaurant/services/tender_service"

# Data Generation
require_relative "clover_restaurant/data_generation/entity_generator"

module CloverRestaurant
  class << self
    attr_accessor :config

    def configure
      self.config ||= Config.new
      yield(config) if block_given?
      config
    end

    def logger
      config.logger
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
    @config ||= Config.new
  end

  # Reset the configuration
  def self.reset_config!
    @config = Config.new
  end
end
