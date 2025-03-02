require_relative "base_generator"

module CloverRestaurant
  module DataGeneration
    class DailyOperationGenerator < BaseGenerator
      def initialize(custom_config = nil)
        super(custom_config)

        # Initialize operation-related services
        @services = {
          employee: ::CloverRestaurant::Services::EmployeeService.new(@config),
          order: ::CloverRestaurant::Services::OrderService.new(@config),
          payment: ::CloverRestaurant::Services::PaymentService.new(@config),
          tip: ::CloverRestaurant::Services::TipService.new(@config),
          refund: ::CloverRestaurant::Services::RefundService.new(@config),
          modifier: ::CloverRestaurant::Services::ModifierService.new(@config)
        }
      end

      def schedule_employees_for_day(date, employees)
        log_info("Scheduling employees for #{date}")

        # Randomly select employees to work today (60-80% of staff)
        employee_count = (employees.size * (0.6 + rand * 0.2)).round
        todays_employees = employees.sample(employee_count)

        # Record shifts
        shifts = []

        # Assign morning/evening shifts
        morning_shift = todays_employees.sample(todays_employees.size / 2)
        evening_shift = todays_employees - morning_shift

        # Morning shift: 8 AM - 4 PM
        morning_shift.each do |employee|
          morning_start = DateTime.parse("#{date} 08:00:00") + rand(0..60).minutes
          morning_end = DateTime.parse("#{date} 16:00:00") + rand(0..60).minutes

          # Clock in
          shift = services[:employee].clock_in(employee["id"])

          if shift && shift["id"]
            # Update shift with specific times
            updated_shift = services[:employee].update_shift(shift["id"], {
                                                               "inTime" => morning_start.to_time.to_i * 1000,
                                                               "outTime" => morning_end.to_time.to_i * 1000
                                                             })

            shifts << updated_shift if updated_shift
          end
        rescue StandardError => e
          log_error("Error creating shift for employee #{employee["id"]}: #{e.message}")
        end

        # Evening shift: 4 PM - midnight
        evening_shift.each do |employee|
          evening_start = DateTime.parse("#{date} 16:00:00") + rand(0..60).minutes
          evening_end = DateTime.parse("#{date} 23:59:59")

          # Clock in
          shift = services[:employee].clock_in(employee["id"])

          if shift && shift["id"]
            # Update shift with specific times
            updated_shift = services[:employee].update_shift(shift["id"], {
                                                               "inTime" => evening_start.to_time.to_i * 1000,
                                                               "outTime" => evening_end.to_time.to_i * 1000
                                                             })

            shifts << updated_shift if updated_shift
          end
        rescue StandardError => e
          log_error("Error creating shift for employee #{employee["id"]}: #{e.message}")
        end

        { employees: todays_employees, shifts: shifts }
      end

      def create_walk_in_orders(date, count, employees, customers, inventory_items, discounts)
        log_info("Creating #{count} walk-in orders for #{date}")

        orders = []

        count.times do
          # Randomly select aspects of the order
          employee = employees.sample
          # 70% of orders have a customer, 30% are anonymous
          customer = rand < 0.7 ? customers.sample : nil

          # Create random time between 11 AM and 10 PM
          hour = rand(11..22)
          minute = rand(0..59)
          order_time = DateTime.parse("#{date}T#{hour}:#{minute}:00")
          timestamp = order_time.to_time.to_i * 1000

          # Create order
          order_data = {
            "createdTime" => timestamp,
            "state" => "OPEN"
          }

          order_data["employee"] = { "id" => employee["id"] } if employee
          order_data["customer"] = { "id" => customer["id"] } if customer

          begin
            order = services[:order].create_order(order_data)

            if order && order["id"]
              # Add items to order (1-10 items)
              item_count = rand(1..9)
              selected_items = inventory_items.sample(item_count)

              selected_items.each do |item|
                # Random quantity between 1 and 3
                quantity = rand(1..3)

                begin
                  line_item = services[:order].add_line_item(order["id"], item["id"], quantity)

                  # Randomly add modifications
                  if rand < 0.3 # 30% chance
                    # Get modifier groups for this item
                    item_modifier_groups = services[:modifier].get_item_modifier_groups(item["id"])

                    if item_modifier_groups && item_modifier_groups["elements"] && !item_modifier_groups["elements"].empty?
                      # Select a random modifier group
                      modifier_group = item_modifier_groups["elements"].sample

                      # Get modifiers for this group
                      modifiers = services[:modifier].get_modifiers(modifier_group["id"])

                      if modifiers && modifiers["elements"] && !modifiers["elements"].empty?
                        # Add a random modifier
                        modifier = modifiers["elements"].sample
                        services[:order].add_modification(order["id"], line_item["id"], modifier["id"])
                      end
                    end
                  end

                  # Add notes sometimes
                  if rand < 0.2 # 20% chance
                    note = ["No onions", "Extra spicy", "On the side", "Gluten free if possible",
                            "Allergy to nuts"].sample
                    services[:order].add_note_to_line_item(order["id"], line_item["id"], note)
                  end
                rescue StandardError => e
                  log_error("Error adding line item to order #{order["id"]}: #{e.message}")
                end
              end

              # Add discount sometimes
              if rand < 0.25 # 25% chance
                begin
                  discount = discounts.sample
                  services[:order].add_discount(order["id"], { "discount" => { "id" => discount["id"] } })
                rescue StandardError => e
                  log_error("Error adding discount to order #{order["id"]}: #{e.message}")
                end
              end

              # Calculate and update total
              begin
                total = services[:order].calculate_order_total(order["id"])
                services[:order].update_order_total(order["id"], total)

                # Get the updated order with total
                updated_order = services[:order].get_order(order["id"])
                orders << updated_order if updated_order
              rescue StandardError => e
                log_error("Error calculating total for order #{order["id"]}: #{e.message}")
                orders << order # Use the original order object
              end
            end
          rescue StandardError => e
            log_error("Error creating walk-in order: #{e.message}")
          end
        end

        orders
      end

      def process_payment_for_order(order)
        return nil unless order && order["id"] && order["total"]

        log_info("Processing payment for order #{order["id"]} with total #{order["total"]}")

        begin
          # 90% card payments, 10% cash
          payment_method = rand < 0.9 ? :card : :cash

          payment = if payment_method == :card
                      services[:payment].simulate_card_payment(order["id"], order["total"])
                    else
                      services[:payment].simulate_cash_payment(order["id"], order["total"])
                    end

          if payment && payment["id"]
            # Add tip (80% of the time)
            return payment unless rand < 0.8

            # Calculate tip (15-25% of the total)
            tip_percentage = rand(15..24)
            tip_amount = (order["total"] * tip_percentage / 100.0).round

            services[:tip].add_tip_to_payment(payment["id"], tip_amount)

            # Get updated payment with tip
            updated_payment = services[:payment].get_payment(payment["id"])
            return updated_payment

          end
        rescue StandardError => e
          log_error("Error processing payment for order #{order["id"]}: #{e.message}")
        end

        nil
      end

      def process_random_refunds(orders, count)
        log_info("Processing #{count} random refunds")

        refunds = []

        # Select random orders to refund
        orders_to_refund = orders.sample([count, orders.size].min)

        orders_to_refund.each do |order|
          # Get payments for this order
          payments = services[:order].get_payments(order["id"])

          next unless payments && payments["elements"] && !payments["elements"].empty?

          payment = payments["elements"].first

          # Decide refund type
          refund_type = rand < 0.7 ? :partial : :full

          if refund_type == :full
            # Full refund
            refund = services[:refund].full_refund(payment["id"], "Customer dissatisfied")
          else
            # Partial refund (25-75% of total)
            refund_percentage = rand(25..74)
            refund_amount = (order["total"] * refund_percentage / 100.0).round
            refund = services[:refund].partial_refund(payment["id"], refund_amount, "Item quality issue")
          end

          refunds << refund if refund && refund["id"]
        rescue StandardError => e
          log_error("Error processing refund for order #{order["id"]}: #{e.message}")
        end

        refunds
      end
    end
  end
end
