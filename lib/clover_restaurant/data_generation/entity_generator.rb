require "json"
require_relative "base_generator"

module CloverRestaurant
  module DataGeneration
    class EntityGenerator < BaseGenerator
      INVENTORY_DATA_PATH = File.expand_path("inventory_data", __dir__)

      def initialize(custom_config = nil, services_manager)
        super(custom_config)
        @services_manager = services_manager
        @services = initialize_services
      end

      def cleanup_entities
        CloverRestaurant::DataGeneration::DeleteAll.new(@config, @services_manager).delete_all_entities
      end

      def create_entities
        log_info("🔄 Checking existing Clover entities before creation...")

        # ✅ Step 1: Fetch Existing Data
        existing_inventory = fetch_existing_inventory
        existing_customers = fetch_existing_customers
        existing_employees = fetch_existing_employees
        existing_discounts = fetch_existing_discounts
        existing_tax_rates = fetch_existing_taxes

        # ✅ Step 2: Create Missing Data
        inventory = ensure_inventory(existing_inventory)
        customers = ensure_customers(existing_customers, 30)
        employees = ensure_employees(existing_employees)
        discounts = ensure_discounts(existing_discounts)
        tax_rates = ensure_tax_rates(existing_tax_rates)

        log_info("✅ Entity creation complete!")

        { inventory:, customers:, employees:, discounts:, tax_rates: }
      end

      private

      ### **🔹 Service Initialization**
      def initialize_services
        {
          inventory: @services_manager.inventory,
          modifier: @services_manager.modifier,
          employee: @services_manager.employee,
          customer: @services_manager.customer,
          discount: @services_manager.discount,
          tax: @services_manager.tax
        }
      end

      ### **🔹 Inventory Handling**
      def ensure_inventory(existing_inventory)
        if existing_inventory[:categories].size > 1 && existing_inventory[:items].size > 1
          log_info("✅ Found existing inventory. Ensuring all items are categorized.")
          ensure_items_have_categories(existing_inventory[:items], existing_inventory[:categories])
          return existing_inventory
        end

        create_inventory(existing_inventory)
      end

      def fetch_existing_inventory
        log_info("🔍 Fetching existing inventory from Clover API...")
        categories = safe_api_call { @services[:inventory].get_categories(100) } || []
        items = safe_api_call { @services[:inventory].get_items(100) } || []

        { categories:, items: }
      end

      def create_inventory(existing_inventory)
        log_info("🔄 Creating inventory from JSON files...")

        items_data = existing_inventory[:items] || load_json("items.json")
        category_names = items_data.map { |item| item["category"] }.uniq

        created_categories = ensure_categories(category_names, existing_inventory[:categories])
        created_items = create_items(items_data, created_categories)

        { categories: created_categories, items: created_items }
      end

      def ensure_categories(category_names, existing_categories)
        return existing_categories unless existing_categories.empty?

        category_names.map do |name|
          category = @services[:inventory].create_category({ "name" => name })
          category || log_error("❌ Failed to create category: #{name}")
        end.compact
      end

      def create_items(items_data, categories)
        items_data.map do |item_data|
          category = categories.find { |c| c["name"] == item_data["category"] }
          next log_error("❌ Category not found for item: #{item_data["name"]}") unless category

          @services[:inventory].assign_item_to_category(item_data["id"], category)
        end.compact
      end

      ### **🔹 Ensure Items Have Categories**
      def ensure_items_have_categories(items, categories)
        categories = categories["elements"]

        uncategorized_items = items["elements"].select { |item| !item["categories"] || item["categories"].empty? }
        return if uncategorized_items.empty?

        binding.pry
        log_info("⚠️ Found #{uncategorized_items.size} uncategorized items. Assigning categories...")

        # Ensure there is at least one category
        if categories.empty?
          log_info("⚠️ No categories found! Creating a default category...")
          categories << create_default_category
        end

        # Assign categories to uncategorized items
        item_category_mapping = {}
        uncategorized_items.each do |item|
          category = categories.sample
          item_category_mapping[item["id"]] = category["id"]
          result = @services[:inventory].assign_item_to_category(item["id"], category)

          if result
            log_info("✅ Successfully assigned categories to #{result[:updated_count]} items")
          else
            log_info("⚠️ Bulk assignment had issues. Falling back to individual assignments...")
          end
        end
      end

      def create_default_category
        log_info("🔄 Creating a default 'Miscellaneous' category...")

        category = @services[:inventory].create_category({ "name" => "Miscellaneous" })
        category || log_error("❌ Failed to create default category")
      end

      ### **🔹 Customer Handling**
      def ensure_customers(existing_customers, count)
        return existing_customers unless existing_customers.empty?

        create_customers(count)
      end

      def fetch_existing_customers
        log_info("🔍 Fetching existing customers from Clover API...")
        safe_api_call { @services[:customer].get_customers(100) } || []
      end

      def create_customers(count)
        log_info("🔄 Creating #{count} customers...")

        count.times.map do |i|
          customer_data = {
            "firstName" => "Customer#{i + 1}",
            "lastName" => "LastName#{i + 1}",
            "email" => "customer#{i + 1}@example.com",
            "phone" => "555-555-5555",
            "marketingAllowed" => false
          }
          @services[:customer].create_customer(customer_data)
        end.compact
      end

      ### **🔹 Employee Handling**
      def ensure_employees(existing_employees)
        return existing_employees unless existing_employees.empty?

        create_employees_and_roles
      end

      def fetch_existing_employees
        log_info("🔍 Fetching existing employees from Clover API...")
        safe_api_call { @services[:employee].get_employees(100) } || []
      end

      ### **🔹 Discount Handling**
      def ensure_discounts(existing_discounts)
        return existing_discounts unless existing_discounts.empty?

        create_discounts
      end

      def fetch_existing_discounts
        log_info("🔍 Fetching existing discounts from Clover API...")
        safe_api_call { @services[:discount].get_discounts(100) } || []
      end

      def create_discounts
        log_info("🔄 Creating discounts from JSON file...")
        discounts_data = load_json("discounts.json")

        discounts_data.map do |discount_data|
          @services[:discount].create_discount({
                                                 "name" => discount_data["name"],
                                                 "rate" => discount_data["rate"],
                                                 "isDefault" => discount_data["isDefault"]
                                               })
        end.compact
      end

      ### **🔹 Tax Handling**
      def ensure_tax_rates(existing_tax_rates)
        return existing_tax_rates if existing_tax_rates.size > 1

        create_tax_rates
      end

      def fetch_existing_taxes
        log_info("🔍 Fetching existing tax rates from Clover API...")
        safe_api_call { @services[:tax].get_tax_rates(100) } || []
      end

      def create_tax_rates
        log_info("🔄 Creating tax rates from JSON file...")
        tax_rates_data = load_json("tax_rates.json")

        tax_rates_data.map do |tax_rate_data|
          @services[:tax].create_tax_rate({
                                            "name" => tax_rate_data["name"],
                                            "rate" => tax_rate_data["rate"],
                                            "isDefault" => tax_rate_data["isDefault"]
                                          })
        end.compact
      end

      ### **🔹 Utility Methods**
      def safe_api_call
        yield
      rescue StandardError
        []
      end

      def load_json(filename)
        JSON.parse(File.read(File.join(INVENTORY_DATA_PATH, filename)))
      rescue StandardError
        log_error("❌ Failed to load #{filename}.")
        []
      end
    end
  end
end
