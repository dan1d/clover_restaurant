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
require_relative "clover_restaurant/errors"
require_relative "clover_restaurant/base_service"
require_relative "clover_restaurant/payment_encryptor"

# Services
require_relative "clover_restaurant/services/index"
# Data Generation (adjust paths to match your structure)
require_relative "clover_restaurant/data_generation/index"
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
