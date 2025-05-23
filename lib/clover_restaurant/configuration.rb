module CloverRestaurant
  class Configuration
    attr_accessor :merchant_id, :api_token, :api_key, :environment, :logger, :log_level, :force_refresh

    def initialize
      load_environment_variables
      @environment = ENV['CLOVER_ENVIRONMENT'] || "https://sandbox.dev.clover.com/"
      @log_level = ENV['LOG_LEVEL'] ? Logger.const_get(ENV['LOG_LEVEL'].upcase) : Logger::INFO
      @logger = setup_logger
      @force_refresh = ENV['FORCE_REFRESH'] == 'true'
      validate!
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
      missing_vars = []
      missing_vars << "CLOVER_MERCHANT_ID" if @merchant_id.nil? || @merchant_id.empty?
      missing_vars << "CLOVER_API_TOKEN" if @api_token.nil? || @api_token.empty?

      unless missing_vars.empty?
        error_message = <<~ERROR
          Missing required environment variables:
          #{missing_vars.join("\n")}

          Please create a .env file in your project root with these variables.
          Example .env file:

          CLOVER_MERCHANT_ID=your_merchant_id_here
          CLOVER_API_TOKEN=your_api_token_here
          CLOVER_ENVIRONMENT=https://sandbox.dev.clover.com/
          LOG_LEVEL=INFO
          FORCE_REFRESH=false
        ERROR
        raise ConfigurationError, error_message
      end
    end

    # Alias for api_token to maintain compatibility with both naming conventions
    def oauth_token
      @api_token
    end

    private

    def load_environment_variables
      begin
        require 'dotenv'
        Dotenv.load
      rescue LoadError
        @logger&.warn "dotenv gem not found, skipping .env file loading"
      end

      @merchant_id = ENV['CLOVER_MERCHANT_ID']
      @api_token = ENV['CLOVER_API_TOKEN']
      @api_key = ENV['CLOVER_API_KEY']
    end
  end
end
