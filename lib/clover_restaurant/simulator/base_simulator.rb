module CloverRestaurant
  module Simulator
    class BaseSimulator
      attr_reader :services_manager, :entity_generator, :logger, :config, :state

      def initialize(options = {})
        setup_configuration
        @logger = @config.logger
        @state = CloverRestaurant::StateManager.new
        setup_services
      end

      private

      def setup_configuration
        CloverRestaurant.configure do |config|
          config.merchant_id = ENV['CLOVER_MERCHANT_ID']
          config.api_token = ENV['CLOVER_API_TOKEN']
          config.environment = ENV['CLOVER_ENVIRONMENT'] || "https://sandbox.dev.clover.com/"
          config.log_level = ENV['LOG_LEVEL'] ? Logger.const_get(ENV['LOG_LEVEL'].upcase) : Logger::INFO
          config.force_refresh = ENV['FORCE_REFRESH'] == 'true'
        end
        @config = CloverRestaurant.config
      end

      def setup_services
        @services_manager = CloverRestaurant::CloverServicesManager.new(@config)
        @entity_generator = CloverRestaurant::DataGeneration::EntityGenerator.new(
          @services_manager.config,
          @services_manager
        )
      end

      def print_header
        puts "\n" + "=" * 80
        puts "CLOVER AUTOMATION".center(80)
        puts "=" * 80 + "\n\n"
        puts "Merchant ID: #{@config.merchant_id}"
        puts "Environment: #{@config.environment}"
      end
    end
  end
end
