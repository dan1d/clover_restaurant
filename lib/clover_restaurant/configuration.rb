module CloverRestaurant
  class Configuration
    attr_accessor :merchant_id, :api_token, :api_key, :environment, :logger, :log_level

    def initialize
      @merchant_id = nil
      @api_token = nil
      @api_key = nil
      @environment = "https://sandbox.dev.clover.com/"
      @log_level = Logger::DEBUG
      @logger = setup_logger
    end

    def setup_logger
      logger = Logger.new($stdout)
      logger.level = @log_level
      logger.formatter = proc do |severity, datetime, progname, msg|
        "[#{datetime.strftime("%Y-%m-%d %H:%M:%S")}] #{severity}: #{msg}\n"
      end
      logger
    end

    def validate!
      raise ConfigurationError, "Merchant ID must be set" unless @merchant_id
      raise ConfigurationError, "Either API token or API key must be set" unless @api_token || @api_key
    end
  end
end
