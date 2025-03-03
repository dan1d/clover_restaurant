# lib/clover_restaurant.rb
require "httparty"
require "json"
require "openssl"
require "base64"
require "logger"
require "faker"
require "active_support/time"

# Base and core components
require_relative "clover_restaurant/version"
require_relative "clover_restaurant/configuration"
require_relative "clover_restaurant/vcr_setup"
require_relative "clover_restaurant/errors"
require_relative "clover_restaurant/base_service"
require_relative "clover_restaurant/payment_encryptor"
require_relative "clover_restaurant/clover_services_manager"

# Services
require "clover_restaurant/base_service"
require "clover_restaurant/services/merchant_service"
require "clover_restaurant/services/order_service"
require "clover_restaurant/services/payment_service"
require "clover_restaurant/services/tax_service"
require "clover_restaurant/services/discount_service"
require "clover_restaurant/services/employee_service"
require "clover_restaurant/services/customer_service"
require "clover_restaurant/services/menu_service"
require "clover_restaurant/services/inventory_service"
require "clover_restaurant/services/modifier_service"
require "clover_restaurant/services/refund_service"
require "clover_restaurant/services/tender_service"
require "clover_restaurant/services/tip_service"
require "clover_restaurant/services/device_service"
# Data Generation (adjust paths to match your structure)
require "clover_restaurant/data_generation/delete_all"
require "clover_restaurant/data_generation/base_generator"
require "clover_restaurant/data_generation/daily_operation_generator"
require "clover_restaurant/data_generation/entity_generator"
require "clover_restaurant/data_generation/analytics_generator"

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
