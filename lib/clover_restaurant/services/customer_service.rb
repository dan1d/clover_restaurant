# lib/clover_restaurant/services/customer_service.rb
module CloverRestaurant
  module Services
    class CustomerService < BaseService
      def get_customers(limit = 99, offset = 0, filter = nil)
        logger.info "=== Fetching customers for merchant #{@config.merchant_id} ==="
        query_params = { limit: limit, offset: offset }
        query_params[:filter] = filter if filter

        make_request(:get, endpoint("customers"), nil)
      end

      def get_customer(customer_id)
        logger.info "=== Fetching customer #{customer_id} for merchant #{@config.merchant_id} ==="
        make_request(:get, endpoint("customers/#{customer_id}"))
      end

      def create_customer(customer_data)
        logger.info "=== Creating new customer for merchant #{@config.merchant_id} ==="

        # Check if customer already exists by phone or email
        if customer_data["phoneNumbers"] && !customer_data["phoneNumbers"].empty?
          phone = customer_data["phoneNumbers"].first["phoneNumber"]
          existing_customer = get_customer_by_phone(phone)
          if existing_customer
            logger.info "Customer with phone #{phone} already exists with ID: #{existing_customer["id"]}, skipping creation"
            return existing_customer
          end
        end

        if customer_data["emailAddresses"] && !customer_data["emailAddresses"].empty?
          email = customer_data["emailAddresses"].first["emailAddress"]
          existing_customer = get_customer_by_email(email)
          if existing_customer
            logger.info "Customer with email #{email} already exists with ID: #{existing_customer["id"]}, skipping creation"
            return existing_customer
          end
        end

        # Validate email address format
        if customer_data["emailAddresses"] && !customer_data["emailAddresses"].empty?
          customer_data["emailAddresses"].each do |email_entry|
            # Ensure email format is valid
            next unless email_entry["emailAddress"] && !valid_email?(email_entry["emailAddress"])

            logger.warn "Invalid email format detected: #{email_entry["emailAddress"]}"
            # Replace with a valid format email
            email_entry["emailAddress"] = generate_valid_email(
              customer_data["firstName"] || "customer",
              customer_data["lastName"] || "example"
            )
            logger.info "Replaced with valid email: #{email_entry["emailAddress"]}"
          end
        end

        logger.info "Customer data: #{customer_data.inspect}"
        make_request(:post, endpoint("customers"), customer_data)
      end

      def update_customer(customer_id, customer_data)
        logger.info "=== Updating customer #{customer_id} for merchant #{@config.merchant_id} ==="

        # Validate email address format for updates too
        if customer_data["emailAddresses"] && !customer_data["emailAddresses"].empty?
          customer_data["emailAddresses"].each do |email_entry|
            # Ensure email format is valid
            next unless email_entry["emailAddress"] && !valid_email?(email_entry["emailAddress"])

            logger.warn "Invalid email format detected: #{email_entry["emailAddress"]}"
            # Replace with a valid format email
            email_entry["emailAddress"] = generate_valid_email(
              customer_data["firstName"] || "customer",
              customer_data["lastName"] || "example"
            )
            logger.info "Replaced with valid email: #{email_entry["emailAddress"]}"
          end
        end

        logger.info "Update data: #{customer_data.inspect}"
        make_request(:post, endpoint("customers/#{customer_id}"), customer_data)
      end

      def delete_customer(customer_id)
        logger.info "=== Deleting customer #{customer_id} for merchant #{@config.merchant_id} ==="
        make_request(:delete, endpoint("customers/#{customer_id}"))
      end

      def search_customers(query)
        logger.info "=== Searching for customers with query: #{query} ==="
        make_request(:get, endpoint("customers"), nil, { filter: query })
      end

      def get_customer_by_phone(phone_number)
        formatted_phone = phone_number.to_s.gsub(/\D/, "")
        logger.info "=== Looking up customer by phone number: #{formatted_phone} ==="

        # Search for customers with this phone number
        result = search_customers("phoneNumber=#{formatted_phone}")

        if result && result["elements"] && !result["elements"].empty?
          logger.info "Found customer by phone: #{result["elements"].first["id"]}"
          return result["elements"].first
        end

        logger.info "No customer found with phone number: #{formatted_phone}"
        nil
      end

      def get_customer_by_email(email)
        logger.info "=== Looking up customer by email: #{email} ==="

        # Search for customers with this email
        result = search_customers("emailAddress=#{email}")

        if result && result["elements"] && !result["elements"].empty?
          logger.info "Found customer by email: #{result["elements"].first["id"]}"
          return result["elements"].first
        end

        logger.info "No customer found with email: #{email}"
        nil
      end

      def add_customer_note(customer_id, note)
        logger.info "=== Adding note to customer #{customer_id} ==="

        # Get current customer first
        customer = get_customer(customer_id)
        unless customer
          logger.error "Customer not found: #{customer_id}"
          return false
        end

        # Append to existing notes or create new
        current_note = customer["note"].to_s
        updated_note = current_note.empty? ? note : "#{current_note}\n---\n#{note}"

        logger.info "Updating note for customer #{customer_id}"
        update_customer(customer_id, { "note" => updated_note })
      end

      def create_or_update_customer(customer_data)
        logger.info "=== Creating or updating customer ==="

        # Check if customer exists by phone, email, or both
        existing_customer = nil

        if customer_data["phoneNumber"] || (customer_data["phoneNumbers"] && !customer_data["phoneNumbers"].empty?)
          phone = customer_data["phoneNumber"] || customer_data["phoneNumbers"].first["phoneNumber"]
          existing_customer = get_customer_by_phone(phone)
          logger.info "Checked for existing customer by phone: #{existing_customer ? "Found" : "Not found"}"
        end

        if !existing_customer && (customer_data["emailAddress"] || (customer_data["emailAddresses"] && !customer_data["emailAddresses"].empty?))
          email = customer_data["emailAddress"] || customer_data["emailAddresses"].first["emailAddress"]
          existing_customer = get_customer_by_email(email)
          logger.info "Checked for existing customer by email: #{existing_customer ? "Found" : "Not found"}"
        end

        if existing_customer
          logger.info "Found existing customer #{existing_customer["id"]}, updating"
          update_customer(existing_customer["id"], customer_data)
          get_customer(existing_customer["id"])
        else
          logger.info "No existing customer found, creating new"
          create_customer(customer_data)
        end
      end

      def get_customer_preferences(customer_id)
        logger.info "=== Fetching preferences for customer #{customer_id} ==="

        customer = get_customer(customer_id)
        unless customer
          logger.error "Customer not found: #{customer_id}"
          return nil
        end

        # Parse any structured data in the metadata field
        metadata = customer["metadata"] || {}

        # Look for preferences
        preferences = metadata["preferences"] || {}

        logger.info "Found preferences: #{preferences.inspect}"

        # Also check note field for any preference indicators
        if customer["note"]
          # Extract preferences from notes (simplified implementation)
          note_preferences = {}
          preference_indicators = %w[prefers likes dislikes allergic favorite]

          preference_indicators.each do |indicator|
            next unless customer["note"].include?(indicator)

            # Very basic extraction - in a real implementation, you'd want
            # more sophisticated parsing
            note_preferences[indicator] = true
          end

          preferences = preferences.merge(note_preferences)
          logger.info "Added preferences from notes: #{note_preferences.inspect}"
        end

        preferences
      end

      def update_customer_preferences(customer_id, preferences)
        logger.info "=== Updating preferences for customer #{customer_id} ==="
        logger.info "New preferences: #{preferences.inspect}"

        customer = get_customer(customer_id)
        unless customer
          logger.error "Customer not found: #{customer_id}"
          return false
        end

        # Get current metadata or create empty hash
        metadata = customer["metadata"] || {}

        # Update preferences
        metadata["preferences"] = preferences

        # Update customer with new metadata
        update_customer(customer_id, { "metadata" => metadata })
      end

      def create_random_customers(num_customers = 10)
        logger.info "=== Creating #{num_customers} random customers ==="

        # Check for existing customers first
        existing_customers = get_customers(limit: 100)
        if existing_customers && existing_customers["elements"] && existing_customers["elements"].size >= num_customers / 2
          logger.info "Found #{existing_customers["elements"].size} existing customers, skipping creation"
          return existing_customers["elements"].first(num_customers)
        end

        created_customers = []
        success_count = 0
        error_count = 0

        num_customers.times do |i|
          # Generate simpler, more predictable data instead of using Faker
          first_name = "Customer#{i + 1}"
          last_name = "Test"

          # Generate phone with format XXX-XXX-XXXX
          phone = "555-#{(100 + i).to_s.rjust(3, "0")}-#{(1000 + i).to_s.rjust(4, "0")}"

          # Generate valid email that will definitely pass validation
          email = generate_valid_email(first_name, last_name)

          customer_data = {
            "firstName" => first_name,
            "lastName" => last_name,
            "phoneNumbers" => [
              {
                "phoneNumber" => phone,
                "type" => "MOBILE"
              }
            ],
            "emailAddresses" => [
              {
                "emailAddress" => email
              }
            ],
            "marketingAllowed" => i.even? # Deterministic instead of random
          }

          # Add address sometimes - use modulo for deterministic behavior
          if i % 10 < 7 # 70% chance - deterministic
            customer_data["addresses"] = [
              {
                "address1" => "#{100 + i} Main St",
                "city" => "Springfield",
                "state" => "IL",
                "zip" => "62701",
                "country" => "US"
              }
            ]
          end

          # Add birthday sometimes - use modulo for deterministic behavior
          if i % 10 < 3 # 30% chance - deterministic
            # Generate a date between 18 and 70 years ago
            year = Time.now.year - (18 + (i % 52)) # Deterministic age 18-70
            month = (1 + (i % 12)).to_s.rjust(2, "0")
            day = (1 + (i % 28)).to_s.rjust(2, "0")
            customer_data["birthDate"] = "#{year}-#{month}-#{day}"
          end

          # Add notes sometimes - use modulo for deterministic behavior
          if i % 10 < 4 # 40% chance - deterministic
            note_options = [
              "Prefers booth seating",
              "Allergic to nuts",
              "Likes extra spicy food",
              "Regular happy hour customer",
              "Celebrates birthday every year with us",
              "Prefers window table",
              "Wine enthusiast",
              "Always orders dessert",
              "Vegan diet",
              "Gluten intolerant"
            ]

            note_index = i % note_options.size
            customer_data["note"] = note_options[note_index]
          end

          logger.info "Creating customer #{i + 1}/#{num_customers}: #{first_name} #{last_name}"
          logger.info "Customer data: #{customer_data.inspect}"

          begin
            # Check if customer already exists by phone or email before creating
            existing_customer = get_customer_by_phone(phone)

            existing_customer ||= get_customer_by_email(email)

            if existing_customer
              logger.info "Customer already exists with ID: #{existing_customer["id"]}, skipping creation"
              created_customers << existing_customer
              success_count += 1
              next
            end

            customer = create_customer(customer_data)

            if customer && customer["id"]
              logger.info "Successfully created customer: #{customer["firstName"]} #{customer["lastName"]} with ID: #{customer["id"]}"
              created_customers << customer
              success_count += 1
            else
              logger.warn "Created customer but received unexpected response: #{customer.inspect}"
              error_count += 1
            end
          rescue StandardError => e
            logger.error "Failed to create customer: #{e.message}"
            error_count += 1
          end
        end

        logger.info "=== Finished creating customers: #{success_count} successful, #{error_count} failed ==="
        created_customers
      end

      private

      def valid_email?(email)
        # Simple email validation regex
        # This checks for basic email format: something@something.something
        email_regex = /\A[^@\s]+@([^@\s]+\.)+[^@\s]+\z/
        !!(email =~ email_regex)
      end

      def generate_valid_email(first_name, last_name)
        # Create a sanitized version of the name for the email
        # Remove special characters and replace spaces with dots
        safe_first = first_name.to_s.downcase.gsub(/[^a-z0-9]/, "")
        safe_last = last_name.to_s.downcase.gsub(/[^a-z0-9]/, "")

        # Add random number to prevent potential duplicates
        random_num = rand(1000..9999)

        # Use common domain for consistency
        "#{safe_first}.#{safe_last}#{random_num}@example.com"
      end
    end
  end
end
