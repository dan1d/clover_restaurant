# lib/clover_restaurant/clover_services_manager.rb

module CloverRestaurant
  class CloverServicesManager
    attr_reader :config, :services

    def initialize(custom_config = nil)
      @config = custom_config || CloverRestaurant.configuration
      @config.validate!

      @services = {}
      @cache = {}
    end

    # Initialize services lazily to avoid creating unnecessary ones
    def method_missing(method_name, *args, &block)
      service_name = method_name.to_s

      # Check if this is a request for a service
      if service_exists?(service_name)
        # Initialize the service if it doesn't exist yet
        @services[service_name] ||= create_service(service_name)
        return @services[service_name]
      end

      # If not a service request, call super
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
      service_names.each do |name|
        @services[name] ||= create_service(name)
      end

      @services
    end

    # Execute an operation with caching
    def with_cache(cache_key, &block)
      return @cache[cache_key] if @cache.key?(cache_key)

      result = block.call
      @cache[cache_key] = result if result
      result
    end

    # Create entities using EntityGenerator with caching
    def create_entities
      return @entity_generator if @entity_generator

      # require_relative "services/data_generation/entity_generator"
      @entity_generator = DataGeneration::EntityGenerator.new(@config)

      # Execute entity creation with caching
      inventory = with_cache(:inventory) { @entity_generator.create_inventory }

      if inventory && inventory.respond_to?(:[], :categories)
        categories = inventory[:categories]
        items = inventory[:items]

        with_cache(:modifier_groups) { @entity_generator.create_modifier_groups(items) }
        with_cache(:tax_rates) { @entity_generator.create_tax_rates(categories) }
        with_cache(:discounts) { @entity_generator.create_discounts }
        with_cache(:employees_and_roles) { @entity_generator.create_employees_and_roles }
        with_cache(:customers) { @entity_generator.create_customers(30) }
        with_cache(:table_layout) { @entity_generator.create_table_layout }
        with_cache(:menus) { @entity_generator.create_menus(categories, items) }
        with_cache(:orders) { @entity_generator.create_orders }
        with_cache(:payments) { @entity_generator.create_payments }
        with_cache(:refunds) { @entity_generator.create_refunds }
        with_cache(:reservations) { @entity_generator.create_reservations }
        with_cache(:taxes) { @entity_generator.create_taxes }
        with_cache(:tenders) { @entity_generator.create_tenders }
        with_cache(:tips) { @entity_generator.create_tips }
      end

      @entity_generator
    end

    private

    def service_exists?(service_name)
      service_names.include?(service_name)
    end

    def create_service(service_name)
      # Convert snake_case to CamelCase
      class_name = service_name.split("_").map(&:capitalize).join

      # Get the service class
      service_class = Services.const_get("#{class_name}Service")

      # Create and return the service instance
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
        reservation
        tax
        tender
        tip
      ]
    end
  end

  # Create a convenience method to access the services manager
  def self.services(custom_config = nil)
    @services_manager ||= CloverServicesManager.new(custom_config)
  end
end
