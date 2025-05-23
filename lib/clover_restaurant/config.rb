require 'logger'

module CloverRestaurant
  class Config
    attr_accessor :merchant_id, :oauth_token, :environment, :log_level, :force_refresh

    def initialize
      @merchant_id = ENV['CLOVER_MERCHANT_ID']
      @oauth_token = ENV['CLOVER_API_TOKEN']
      @environment = ENV['CLOVER_ENVIRONMENT'] || 'https://sandbox.dev.clover.com/'
      @log_level = ENV['LOG_LEVEL'] ? Logger.const_get(ENV['LOG_LEVEL']) : Logger::INFO
      @force_refresh = ENV['FORCE_REFRESH'] == 'true'

      validate!
    end

    def validate!
      raise "CLOVER_MERCHANT_ID environment variable is required" unless @merchant_id
      raise "CLOVER_API_TOKEN environment variable is required" unless @oauth_token

      # Ensure environment URL ends with a slash
      @environment = "#{@environment}/" unless @environment.end_with?('/')

      # Strip any trailing spaces
      @merchant_id = @merchant_id.strip
      @oauth_token = @oauth_token.strip
      @environment = @environment.strip

      true
    end

    def logger
      @logger ||= Logger.new(STDOUT).tap do |log|
        log.level = @log_level
        log.formatter = proc do |severity, datetime, progname, msg|
          formatted_datetime = datetime.strftime("%Y-%m-%d %H:%M:%S")
          "[#{formatted_datetime}] #{severity}: #{msg}\n"
        end
      end
    end
  end
end
