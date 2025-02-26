# lib/clover_restaurant/services/reservation_service.rb
module CloverRestaurant
  module Services
    class ReservationService < BaseService
      def get_reservations(limit = 100, offset = 0, filter = nil)
        logger.info "Fetching reservations for merchant #{@config.merchant_id}"
        query_params = { limit: limit, offset: offset }
        query_params[:filter] = filter if filter

        make_request(:get, endpoint("reservations"), nil, query_params)
      end

      def get_reservation(reservation_id)
        logger.info "Fetching reservation #{reservation_id} for merchant #{@config.merchant_id}"
        make_request(:get, endpoint("reservations/#{reservation_id}"))
      end

      def create_reservation(reservation_data)
        logger.info "Creating new reservation for merchant #{@config.merchant_id}"
        make_request(:post, endpoint("reservations"), reservation_data)
      end

      def update_reservation(reservation_id, reservation_data)
        logger.info "Updating reservation #{reservation_id} for merchant #{@config.merchant_id}"
        make_request(:post, endpoint("reservations/#{reservation_id}"), reservation_data)
      end

      def delete_reservation(reservation_id)
        logger.info "Deleting reservation #{reservation_id} for merchant #{@config.merchant_id}"
        make_request(:delete, endpoint("reservations/#{reservation_id}"))
      end

      def get_reservations_for_date(date)
        logger.info "Fetching reservations for date #{date}"

        start_time = DateTime.parse("#{date}T00:00:00").to_time.to_i * 1000
        end_time = DateTime.parse("#{date}T23:59:59").to_time.to_i * 1000

        filter = "time>=#{start_time} AND time<=#{end_time}"

        get_reservations(1000, 0, filter)
      end

      def get_reservations_for_customer(customer_id)
        logger.info "Fetching reservations for customer #{customer_id}"

        filter = "customer.id=#{customer_id}"

        get_reservations(1000, 0, filter)
      end

      def get_reservations_for_table(table_id)
        logger.info "Fetching reservations for table #{table_id}"

        filter = "table.id=#{table_id}"

        get_reservations(1000, 0, filter)
      end

      def make_customer_reservation(customer_data, reservation_time, party_size, table_id = nil, special_requests = nil)
        logger.info "Making a reservation for #{party_size} people at #{reservation_time}"

        # First, get or create the customer
        customer_service = CustomerService.new(@config)
        customer = customer_service.create_or_update_customer(customer_data)

        return false unless customer && customer["id"]

        # Convert time to milliseconds since epoch
        timestamp = DateTime.parse(reservation_time.to_s).to_time.to_i * 1000

        # Prepare reservation data
        reservation_data = {
          "customer" => { "id" => customer["id"] },
          "time" => timestamp,
          "partySize" => party_size
        }

        # Add table if provided
        reservation_data["table"] = { "id" => table_id } if table_id

        # Add special requests if provided
        reservation_data["specialRequests"] = special_requests if special_requests

        create_reservation(reservation_data)
      end

      def find_available_tables(reservation_time, party_size)
        logger.info "Finding available tables for #{party_size} people at #{reservation_time}"

        # Get all tables
        table_service = TableService.new(@config)
        tables = table_service.get_tables

        return [] unless tables && tables["elements"]

        # Filter tables by capacity
        suitable_tables = tables["elements"].select do |table|
          max_seats = table["maxSeats"] || 0
          max_seats >= party_size
        end

        # Convert time to milliseconds since epoch
        requested_time = DateTime.parse(reservation_time.to_s).to_time.to_i * 1000

        # Assume reservations are 2 hours long
        reservation_duration = 2 * 60 * 60 * 1000 # 2 hours in milliseconds
        start_window = requested_time - reservation_duration
        end_window = requested_time + reservation_duration

        # Get reservations for the time window
        filter = "time>=#{start_window} AND time<=#{end_window}"
        existing_reservations = get_reservations(1000, 0, filter)

        return suitable_tables unless existing_reservations && existing_reservations["elements"]

        # Filter out tables that are already reserved
        suitable_tables.reject do |table|
          table_id = table["id"]

          existing_reservations["elements"].any? do |reservation|
            reservation["table"] && reservation["table"]["id"] == table_id
          end
        end
      end

      def suggest_reservation_times(date, party_size, interval_minutes = 30)
        logger.info "Suggesting reservation times for #{party_size} people on #{date}"

        # Define restaurant hours (assuming 11 AM to 10 PM)
        opening_hour = 11
        closing_hour = 22

        # Generate time slots throughout the day
        suggested_times = []

        current_time = DateTime.parse("#{date}T#{opening_hour}:00:00")
        closing_time = DateTime.parse("#{date}T#{closing_hour}:00:00")

        while current_time <= closing_time
          # Check if tables are available for this time slot
          available_tables = find_available_tables(current_time, party_size)

          if available_tables.any?
            suggested_times << {
              "time" => current_time,
              "availableTables" => available_tables.length
            }
          end

          # Move to next time slot
          current_time += Rational(interval_minutes, 1440) # Add interval_minutes
        end

        suggested_times
      end

      def check_in_reservation(reservation_id, table_id = nil)
        logger.info "Checking in reservation #{reservation_id}"

        reservation_data = {
          "status" => "SEATED",
          "checkedIn" => true,
          "checkedInTime" => (Time.now.to_i * 1000)
        }

        # Assign specific table if provided
        reservation_data["table"] = { "id" => table_id } if table_id

        update_reservation(reservation_id, reservation_data)
      end

      def cancel_reservation(reservation_id, reason = nil)
        logger.info "Canceling reservation #{reservation_id}"

        reservation_data = {
          "status" => "CANCELED"
        }

        reservation_data["cancelReason"] = reason if reason

        update_reservation(reservation_id, reservation_data)
      end

      def no_show_reservation(reservation_id)
        logger.info "Marking reservation #{reservation_id} as no-show"

        update_reservation(reservation_id, { "status" => "NO_SHOW" })
      end

      def complete_reservation(reservation_id)
        logger.info "Completing reservation #{reservation_id}"

        update_reservation(reservation_id, { "status" => "COMPLETED" })
      end

      def generate_daily_reservation_report(date = Date.today)
        logger.info "Generating reservation report for #{date}"

        # Get reservations for the specified date
        reservations = get_reservations_for_date(date)

        return nil unless reservations && reservations["elements"]

        # Compile report data
        report = {
          "date" => date.to_s,
          "totalReservations" => reservations["elements"].length,
          "totalGuests" => 0,
          "statusCounts" => {},
          "hourlyDistribution" => {},
          "partySizeDistribution" => {},
          "reservationsByTable" => {}
        }

        reservations["elements"].each do |reservation|
          # Count total guests
          party_size = reservation["partySize"] || 0
          report["totalGuests"] += party_size

          # Count by status
          status = reservation["status"] || "PENDING"
          report["statusCounts"][status] ||= 0
          report["statusCounts"][status] += 1

          # Hourly distribution
          if reservation["time"]
            hour = Time.at(reservation["time"] / 1000).strftime("%H")
            report["hourlyDistribution"][hour] ||= 0
            report["hourlyDistribution"][hour] += 1
          end

          # Party size distribution
          party_size_key = case party_size
                           when 0..2 then "1-2"
                           when 3..4 then "3-4"
                           when 5..6 then "5-6"
                           when 7..10 then "7-10"
                           else "10+"
                           end

          report["partySizeDistribution"][party_size_key] ||= 0
          report["partySizeDistribution"][party_size_key] += 1

          # Table distribution
          next unless reservation["table"] && reservation["table"]["id"]

          table_id = reservation["table"]["id"]
          table_name = reservation["table"]["name"] || "Table #{table_id}"

          report["reservationsByTable"][table_id] ||= {
            "name" => table_name,
            "count" => 0
          }

          report["reservationsByTable"][table_id]["count"] += 1
        end

        report
      end

      def create_random_reservations(num_reservations = 10, start_date = Date.today, days_ahead = 7)
        logger.info "Creating #{num_reservations} random reservations"

        # Get customers
        customer_service = CustomerService.new(@config)
        customers = customer_service.get_customers

        # Create some random customers if none exist
        if !customers || !customers["elements"] || customers["elements"].empty?
          customers = { "elements" => customer_service.create_random_customers(5) }
        end

        # Get tables
        table_service = TableService.new(@config)
        tables = table_service.get_tables

        # Create some tables if none exist
        if !tables || !tables["elements"] || tables["elements"].empty?
          table_layout = table_service.create_standard_restaurant_layout
          return [] unless table_layout && table_layout["tables"]

          tables = { "elements" => table_layout["tables"] }

          # Can't create reservations without tables

        end

        return [] unless customers["elements"] && tables["elements"]

        # Generate random reservations
        created_reservations = []

        num_reservations.times do
          # Pick random customer
          customer = customers["elements"].sample

          # Pick random table
          table = tables["elements"].sample

          # Generate random date within range
          random_days = rand(0..days_ahead)
          reservation_date = start_date + random_days

          # Generate random time between 11 AM and 9 PM
          hour = rand(11..21)
          minute = [0, 15, 30, 45].sample

          reservation_time = DateTime.parse("#{reservation_date}T#{hour}:#{minute}:00")

          # Generate random party size (appropriate for the table)
          max_seats = table["maxSeats"] || 4
          party_size = rand(1..max_seats)

          # Random special requests
          special_requests = nil
          if rand < 0.3 # 30% chance of special request
            special_requests_options = [
              "Window table preferred",
              "Celebrating a birthday",
              "Celebrating an anniversary",
              "Highchair needed",
              "Wheelchair access required",
              "Allergic to nuts",
              "Gluten-free options needed",
              "Vegetarian options needed",
              "Business dinner"
            ]
            special_requests = special_requests_options.sample
          end

          # Create the reservation
          reservation_data = {
            "customer" => { "id" => customer["id"] },
            "table" => { "id" => table["id"] },
            "time" => reservation_time.to_time.to_i * 1000,
            "partySize" => party_size,
            "status" => "PENDING"
          }

          reservation_data["specialRequests"] = special_requests if special_requests

          reservation = create_reservation(reservation_data)

          created_reservations << reservation if reservation && reservation["id"]
        end

        created_reservations
      end
    end
  end
end
