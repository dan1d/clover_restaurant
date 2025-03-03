require "json"
require_relative "base_generator"

module CloverRestaurant
  module DataGeneration
    class EntityGenerator < BaseGenerator
      INVENTORY_DATA_PATH = File.expand_path("inventory_data", __dir__)

      def initialize(custom_config = nil, services_manager)
        super(custom_config)
        @services_manager = services_manager

        @services = {
          inventory: @services_manager.inventory,
          modifier: @services_manager.modifier,
          employee: @services_manager.employee,
          customer: @services_manager.customer,
          discount: @services_manager.discount,
          tax: @services_manager.tax
        }

        @entity_cache = {}
      end

      def cleanup_entities
        # use CloverRestaurant::DataGeneration::DeleteAll
        # to delete all entities
        CloverRestaurant::DataGeneration::DeleteAll.new(@config, @services_manager).delete_all_entities
      end

      def create_entities
        log_info("🔄 Checking existing Clover entities before creation...")

        # ✅ Step 1: Fetch Existing Data
        existing_inventory = fetch_existing_inventory
        existing_categories = existing_inventory[:categories] || []
        existing_items = existing_inventory[:items] || []

        existing_customers = fetch_existing_customers
        existing_employees = fetch_existing_employees
        existing_discounts = fetch_existing_discounts
        existing_tax_rates = fetch_existing_taxes

        # ✅ Step 2: Create Missing Data
        # Only create inventory if we don't have enough items
        inventory = if existing_items.length > 1
                      { categories: existing_categories, items: existing_items }
                    else
                      create_inventory(existing_categories)
                    end

        customers = existing_customers.empty? ? create_customers(30) : existing_customers
        employees = existing_employees.empty? ? create_employees_and_roles : existing_employees
        discounts = existing_discounts.empty? ? create_discounts : existing_discounts
        tax_rates = existing_tax_rates.empty? || existing_tax_rates.length <= 1 ? create_tax_rates : existing_tax_rates

        log_info("✅ Entity creation complete!")

        {
          inventory: inventory,
          customers: customers,
          employees: employees,
          discounts: discounts,
          tax_rates: tax_rates
        }
      end

      def create_discounts
        log_info("🔄 Creating discounts from JSON file...")

        # Load discounts from JSON
        discounts_json_path = File.join(INVENTORY_DATA_PATH, "discounts.json")
        discounts_data = JSON.parse(File.read(discounts_json_path))

        # Fetch existing discounts
        existing_discounts = fetch_existing_discounts

        # Check if there are fewer than the required number of discounts
        if existing_discounts.size < discounts_data.size
          log_info("⚠️ Found #{existing_discounts.size} discounts. Creating default discounts...")

          # Create discounts
          created_discounts = []
          discounts_data.each do |discount_data|
            discount = @services[:discount].create_discount({
                                                              "name" => discount_data["name"],
                                                              "rate" => discount_data["rate"],
                                                              "isDefault" => discount_data["isDefault"]
                                                            })

            if discount && discount["id"]
              log_info("✅ Created discount: #{discount["name"]} (ID: #{discount["id"]})")
              created_discounts << discount
            else
              log_error("❌ Failed to create discount: #{discount_data["name"]}")
            end
          end

          created_discounts
        else
          log_info("✅ Found #{existing_discounts.size} existing discounts, skipping creation.")
          existing_discounts
        end
      end

      def get_category(category)
        {
          "name" => category["name"],
          "id" => category["id"]
        }
      end

      # Generate inventory from JSON files
      def create_inventory(existing_categories = [])
        log_info("🔄 Creating inventory from JSON files...")

        # Load items from JSON
        items_json_path = File.join(INVENTORY_DATA_PATH, "items.json")
        items_data = JSON.parse(File.read(items_json_path))

        # Use existing categories or create new ones
        created_categories = existing_categories
        if existing_categories.empty? || existing_categories.length < 1
          # Extract unique categories from items data
          category_names = items_data.map { |item| item["category"] }.uniq
          log_info("📂 Found categories in items.json: #{category_names.join(", ")}")

          # Create categories in Clover
          created_categories = create_categories(category_names)
          log_info("✅ Created categories: #{created_categories.map { |c| c["name"] }.join(", ")}")
        else
          log_info("✅ Using #{existing_categories.size} existing categories.")
        end

        # Create items and assign to categories
        created_items = []
        items_data.each do |item_data|
          # Find matching category for this item
          category = nil
          category = created_categories.find { |c| c["name"] == item_data["category"] } if item_data["category"]

          # Use a random category if no specific match found
          category ||= created_categories.sample

          # Create the item with category assignment
          item = create_item_with_category(item_data, category["id"])

          created_items << item if item
        end

        log_info("✅ Created #{created_items.size} items with category assignments.")

        {
          categories: created_categories,
          items: created_items
        }
      end

      # Create categories in Clover
      def create_categories(category_names)
        log_info("🔄 Creating categories...")

        category_names.map do |name|
          category = @services[:inventory].create_category({ "name" => name })
          if category && category["id"]
            log_info("✅ Created category: #{name} (ID: #{category["id"]})")
            category
          else
            log_error("❌ Failed to create category: #{name}")
            nil
          end
        end.compact
      end

      # Create an item and assign it to a category
      def create_item_with_category(item_data, category_id)
        log_info("🔄 Creating item: #{item_data["name"]}...")

        # Create the item
        item = @services[:inventory].create_item({
                                                   "name" => item_data["name"],
                                                   "price" => item_data["price"],
                                                   "priceType" => "FIXED",
                                                   "defaultTaxRates" => true,
                                                   "cost" => 0,
                                                   "isRevenue" => true,
                                                   "categories" => [{ "id" => category_id }]
                                                 })

        if item && item["id"]
          log_info("✅ Created item: #{item["name"]} with category ID: #{category_id}")
          item
        else
          log_error("❌ Failed to create item: #{item_data["name"]}")
          nil
        end
      end

      ## ✅ New: Fetch Existing Customers
      def fetch_existing_customers
        log_info("🔍 Fetching existing customers from Clover API...")
        customers = begin
          @services[:customer].get_customers(100)
        rescue StandardError
          []
        end
        return customers["elements"] if customers && customers["elements"]

        []
      end

      ## ✅ New: Fetch Existing Employees
      def fetch_existing_employees
        log_info("🔍 Fetching existing employees from Clover API...")
        employees = begin
          @services[:employee].get_employees(100)
        rescue StandardError
          []
        end
        return employees["elements"] if employees && employees["elements"]

        []
      end

      ## ✅ New: Fetch Existing Inventory (Categories & Items)
      def fetch_existing_inventory
        log_info("🔍 Fetching existing inventory (categories & items) from Clover API...")

        categories = begin
          @services[:inventory].get_categories(100)
        rescue StandardError
          []
        end
        items = begin
          @services[:inventory].get_items(100)
        rescue StandardError
          []
        end

        categories = categories["elements"] if categories && categories["elements"]
        items = items["elements"] if items && items["elements"]

        { categories: categories || [], items: items || [] }
      end

      ## ✅ New: Fetch Existing Discounts
      def fetch_existing_discounts
        log_info("🔍 Fetching existing discounts from Clover API...")
        discounts = begin
          @services[:discount].get_discounts(100)
        rescue StandardError
          []
        end
        return discounts["elements"] if discounts && discounts["elements"]

        []
      end

      def create_tax_rates
        log_info("🔄 Creating tax rates from JSON file...")

        # Load tax rates from JSON
        tax_rates_json_path = File.join(INVENTORY_DATA_PATH, "tax_rates.json")
        tax_rates_data = JSON.parse(File.read(tax_rates_json_path))

        # Fetch existing tax rates
        existing_tax_rates = fetch_existing_taxes

        # Check if there are fewer than 1 tax rates (excluding NO_TAX_APPLIED)
        if existing_tax_rates.size <= 1
          log_info("⚠️ Found #{existing_tax_rates.size} tax rates. Creating default tax rates...")

          # Create tax rates
          created_tax_rates = []
          tax_rates_data.each do |tax_rate_data|
            tax_rate = @services[:tax].create_tax_rate({
                                                         "name" => tax_rate_data["name"],
                                                         "rate" => tax_rate_data["rate"],
                                                         "isDefault" => tax_rate_data["isDefault"]
                                                       })

            if tax_rate && tax_rate["id"]
              log_info("✅ Created tax rate: #{tax_rate["name"]} (ID: #{tax_rate["id"]})")
              created_tax_rates << tax_rate
            else
              log_error("❌ Failed to create tax rate: #{tax_rate_data["name"]}")
            end
          end

          created_tax_rates
        else
          log_info("✅ Found #{existing_tax_rates.size} existing tax rates, skipping creation.")
          existing_tax_rates
        end
      end

      ## ✅ New: Fetch Existing Tax Rates
      def fetch_existing_taxes
        log_info("🔍 Fetching existing tax rates from Clover API...")
        tax_rates = begin
          @services[:tax].get_tax_rates(100)
        rescue StandardError
          []
        end
        return tax_rates["elements"] if tax_rates && tax_rates["elements"]

        []
      end

      # Create customers
      def create_customers(count = 30)
        log_info("🔄 Creating #{count} customers...")

        customers = []
        count.times do |i|
          customer_data = {
            "firstName" => "Customer#{i + 1}",
            "lastName" => "LastName#{i + 1}",
            "email" => "customer#{i + 1}@example.com",
            "phone" => "555-555-5555",
            "marketingAllowed" => false
          }

          customer = @services[:customer].create_customer(customer_data)
          if customer && customer["id"]
            log_info("✅ Created customer: #{customer["firstName"]} #{customer["lastName"]} (ID: #{customer["id"]})")
            customers << customer
          else
            log_error("❌ Failed to create customer: Customer#{i + 1}")
          end
        end

        customers
      end
    end
  end
end
