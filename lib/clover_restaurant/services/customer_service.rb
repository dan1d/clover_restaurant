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

      def create_random_customers(count = 20)
        logger.info "Creating #{count} random customers"

        # Define realistic customer data
        first_names = [
          "James", "Mary", "John", "Patricia", "Robert", "Jennifer", "Michael", "Linda",
          "William", "Elizabeth", "David", "Barbara", "Richard", "Susan", "Joseph", "Jessica",
          "Thomas", "Sarah", "Charles", "Karen", "Christopher", "Nancy", "Daniel", "Lisa",
          "Matthew", "Betty", "Anthony", "Margaret", "Mark", "Sandra", "Donald", "Ashley",
          "Steven", "Kimberly", "Paul", "Emily", "Andrew", "Donna", "Joshua", "Michelle",
          "Emma", "Olivia", "Ava", "Isabella", "Sophia", "Charlotte", "Mia", "Amelia",
          "Harper", "Evelyn", "Abigail", "Emily", "Elizabeth", "Mila", "Ella", "Avery",
          "Sofia", "Camila", "Aria", "Scarlett", "Victoria", "Madison", "Luna", "Grace"
        ]

        last_names = [
          "Smith", "Johnson", "Williams", "Brown", "Jones", "Garcia", "Miller", "Davis",
          "Rodriguez", "Martinez", "Hernandez", "Lopez", "Gonzalez", "Wilson", "Anderson",
          "Thomas", "Taylor", "Moore", "Jackson", "Martin", "Lee", "Perez", "Thompson",
          "White", "Harris", "Sanchez", "Clark", "Ramirez", "Lewis", "Robinson", "Walker",
          "Young", "Allen", "King", "Wright", "Scott", "Torres", "Nguyen", "Hill", "Flores",
          "Chen", "Lee", "Wang", "Yang", "Zhao", "Wu", "Zhou", "Xu", "Sun", "Ma", "Zhu",
          "Li", "Zhang", "Liu", "Patel", "Singh", "Kumar", "Shah", "Sharma", "Murphy",
          "O'Brien", "Ryan", "O'Connor", "Walsh", "O'Sullivan", "McCarthy", "O'Neill"
        ]

        email_domains = ["gmail.com", "yahoo.com", "hotmail.com", "outlook.com", "aol.com", "icloud.com"]
        phone_area_codes = ["212", "646", "917", "347", "718", "516", "914", "631", "201", "732"]

        created_customers = []

        count.times do
          # Generate random customer data
          first_name = first_names.sample
          last_name = last_names.sample
          email = "#{first_name.downcase}.#{last_name.downcase}#{rand(100..999)}@#{email_domains.sample}"
          phone = "#{phone_area_codes.sample}#{rand(100..999)}#{rand(1000..9999)}"

          # Format phone number nicely
          formatted_phone = "(#{phone[0..2]}) #{phone[3..5]}-#{phone[6..9]}"

          # Create marketing preferences (60% chance to opt in)
          marketing_allowed = rand < 0.6

          # Create customer data
          customer_data = {
            "firstName" => first_name,
            "lastName" => last_name,
            "emailAddress" => email,
            "phoneNumber" => formatted_phone,
            "marketingAllowed" => marketing_allowed
          }

          # Add optional address (30% chance)
          if rand < 0.3
            customer_data["address"] = generate_random_address
          end

          # Create the customer
            customer = create_customer(customer_data)
            if customer && customer["id"]
            logger.info "✅ Created customer: #{customer["firstName"]} #{customer["lastName"]}"
              created_customers << customer
            else
            logger.error "❌ Failed to create customer: #{customer_data["firstName"]} #{customer_data["lastName"]}"
          end
        end

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

      def generate_random_address
        # NYC-focused addresses
        streets = [
          "Broadway", "Park Avenue", "Madison Avenue", "5th Avenue", "Lexington Avenue",
          "Amsterdam Avenue", "Columbus Avenue", "West End Avenue", "Riverside Drive",
          "Central Park West", "York Avenue", "1st Avenue", "2nd Avenue", "3rd Avenue"
        ]

        street_types = ["Street", "Avenue", "Place", "Road", "Lane", "Boulevard"]
        boroughs = ["Manhattan", "Brooklyn", "Queens", "Bronx", "Staten Island"]
        zip_codes = {
          "Manhattan" => ["10001", "10002", "10003", "10011", "10012", "10013", "10014", "10016", "10017", "10018", "10019", "10020", "10021", "10022", "10023", "10024", "10025", "10026", "10027", "10028"],
          "Brooklyn" => ["11201", "11205", "11215", "11217", "11220", "11221", "11222", "11223", "11224", "11225", "11226", "11228", "11229", "11230", "11231", "11232", "11233", "11234", "11235", "11236"],
          "Queens" => ["11101", "11102", "11103", "11104", "11105", "11106", "11354", "11355", "11356", "11357", "11358", "11359", "11360", "11361", "11362", "11363", "11364", "11365", "11366", "11367"],
          "Bronx" => ["10451", "10452", "10453", "10454", "10455", "10456", "10457", "10458", "10459", "10460", "10461", "10462", "10463", "10464", "10465", "10466", "10467", "10468", "10469", "10470"],
          "Staten Island" => ["10301", "10302", "10303", "10304", "10305", "10306", "10307", "10308", "10309", "10310", "10311", "10312", "10313", "10314"]
        }

        # Generate address components
        street_number = rand(1..999)
        street = streets.sample
        apt_number = rand < 0.7 ? "Apt #{rand(1..20)}#{('A'..'F').to_a.sample}" : nil
        borough = boroughs.sample
        zip = zip_codes[borough].sample

        # Build address
        address = {
          "address1" => "#{street_number} #{street}",
          "city" => "New York",
          "state" => "NY",
          "zip" => zip
        }

        # Add apartment number if present
        address["address2"] = apt_number if apt_number

        address
      end
    end
  end
end
