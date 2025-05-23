require "clover_restaurant/payment_encryptor"
require "clover_restaurant/configuration"

module CloverRestaurant
  class CloverServicesManager
    attr_reader :config, :inventory, :employee, :tax, :customer, :tender, :discount, :order

    def initialize(config = nil)
      @config = config || Config.new

      # Initialize all services with the same config
      @inventory = Services::InventoryService.new(@config)
      @employee = Services::EmployeeService.new(@config)
      @tax = Services::TaxService.new(@config)
      @customer = Services::CustomerService.new(@config)
      @tender = Services::TenderService.new(@config)
      @discount = Services::DiscountService.new(@config)
      @order = Services::OrderService.new(@config)
    end

    # Initialize services lazily to avoid creating unnecessary ones
    def method_missing(method_name, *args, &block)
      service_name = method_name.to_s

      if service_exists?(service_name)
        @services[service_name] ||= create_service(service_name)
        return @services[service_name]
      end

      super
    end

    def respond_to_missing?(method_name, include_private = false)
      service_exists?(method_name.to_s) || super
    end

    # Clear all cached responses
    def clear_cache
      @cache = {}
      true
    end

    # Get all service instances (initializing them if needed)
    def all_services
      service_names.each { |name| @services[name] ||= create_service(name) }
      @services
    end

    # Ensure tenders exist before creating them
    def ensure_tenders_exist
      existing_tenders = begin
        tender.get_tenders["elements"]
      rescue StandardError
        []
      end
      return if existing_tenders.size > 1

      logger.info "🛠 Creating standard tenders..."
      tender.create_standard_tenders
    end

    def payment_keys
      @payment_keys ||= fetch_payment_keys
    end

    private

    def fetch_payment_keys
      logger.info "=== Fetching Clover payment encryption keys ==="
      response = begin
        @services["payment"].get_payment_keys
      rescue StandardError
        nil
      end

      if response
        {
          modulus: response["modulus"],
          exponent: response["exponent"],
          prefix: response["prefix"]
        }
      else
        logger.error "❌ Failed to retrieve payment keys from Clover API"
        nil
      end
    end

    def service_exists?(service_name)
      service_names.include?(service_name)
    end

    def create_service(service_name)
      class_name = service_name.split("_").map(&:capitalize).join
      service_class = Services.const_get("#{class_name}Service")
      service_class.new(@config)
    end

    def service_names
      %w[
        merchant
        inventory
        modifier
        employee
        customer
        table
        menu
        discount
        tax_rate
        order
        payment
        refund
        tax
        tender
        tip
        device
      ]
    end
  end

  # Create a convenience method to access the services manager
  def self.services(custom_config = nil)
    @services_manager ||= CloverServicesManager.new(custom_config)
  end
end
