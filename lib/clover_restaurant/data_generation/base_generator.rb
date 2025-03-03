require "pry"
module CloverRestaurant
  module DataGeneration
    class BaseGenerator
      attr_reader :config, :logger, :services

      def initialize(custom_config = nil)
        @config = custom_config || CloverRestaurant.configuration
        @logger = @config.logger

        # Initialize all services
        @services = {}
      end

      def log_info(message)
        logger.info(message)
      end

      def log_error(message)
        logger.error(message)
      end
    end
  end
end
