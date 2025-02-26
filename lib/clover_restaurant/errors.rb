module CloverRestaurant
  class Error < StandardError; end
  class ConfigurationError < Error; end
  class APIError < Error; end
  class ResourceNotFoundError < APIError; end
  class AuthenticationError < APIError; end
  class RateLimitError < APIError; end
  class ServiceError < APIError; end
end
