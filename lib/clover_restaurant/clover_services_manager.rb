require "clover_restaurant/payment_encryptor"
require "clover_restaurant/config"

module CloverRestaurant
  class CloverServicesManager
    attr_reader :config, :inventory, :employee, :tax, :customer, :tender, :discount, :order, :merchant, :payment

    def initialize(config = nil)
      @config = config || Config.new
      @services = {} # Initialize @services hash

      # Initialize all services with the same config and a reference to this manager
      @inventory = Services::InventoryService.new(@config, self)
      @employee = Services::EmployeeService.new(@config, self)
      @tax = Services::TaxService.new(@config, self)
      @customer = Services::CustomerService.new(@config, self)
      @tender = Services::TenderService.new(@config, self)
      @discount = Services::DiscountService.new(@config, self)
      @order = Services::OrderService.new(@config, self)
      @merchant = Services::MerchantService.new(@config, self)
      @payment = Services::PaymentService.new(@config, self)
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
        payment.get_payment_keys
      rescue StandardError => e
        logger.error "Error fetching payment keys: #{e.message}"
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
      service_class.new(@config, self)
    end

    def service_names
      %w[
        inventory
        employee
        customer
        discount
        tax
        tender
        order
        merchant
        payment
      ]
    end
  end

  # Create a convenience method to access the services manager
  def self.services(custom_config = nil)
    @services_manager ||= CloverServicesManager.new(custom_config)
  end
end
