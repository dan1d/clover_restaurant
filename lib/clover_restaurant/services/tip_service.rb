# lib/clover_restaurant/services/tip_service.rb
module CloverRestaurant
  module Services
    class TipService < BaseService
      def get_tips(limit = 100, offset = 0)
        logger.info "=== Fetching tips for merchant #{@config.merchant_id} ==="
        make_request(:get, endpoint("payments"), nil, { filter: "tipAmount>0", limit: limit, offset: offset })
      end

      def get_tips_by_employee(employee_id, start_date = nil, end_date = nil)
        logger.info "=== Fetching tips for employee #{employee_id} ==="

        filter = "tipAmount>0 AND employee.id=#{employee_id}"

        if start_date
          start_timestamp = DateTime.parse(start_date.to_s).to_time.to_i * 1000
          filter += " AND createdTime>=#{start_timestamp}"
        end

        if end_date
          end_timestamp = DateTime.parse(end_date.to_s).to_time.to_i * 1000
          filter += " AND createdTime<=#{end_timestamp}"
        end

        make_request(:get, endpoint("payments"), nil, { filter: filter, limit: 1000 })
      end

      def add_tip_to_payment(payment_id, tip_amount)
        logger.info "=== Adding tip of #{tip_amount} to payment #{payment_id} ==="

        # Check if payment already has this tip amount
        payment = get_payment(payment_id)
        if payment && payment["tipAmount"] == tip_amount
          logger.info "Payment #{payment_id} already has tip amount #{tip_amount}, skipping"
          return payment
        end

        make_request(:post, endpoint("payments/#{payment_id}"), {
                       "tipAmount" => tip_amount.to_i
                     })
      end

      def adjust_tip(payment_id, tip_amount)
        logger.info "=== Adjusting tip to #{tip_amount} for payment #{payment_id} ==="

        # Check if payment already has this tip amount
        payment = get_payment(payment_id)
        if payment && payment["tipAmount"] == tip_amount
          logger.info "Payment #{payment_id} already has tip amount #{tip_amount}, skipping"
          return payment
        end

        make_request(:post, endpoint("payments/#{payment_id}/tip"), {
                       "tipAmount" => tip_amount.to_i
                     })
      end

      def calculate_tip_suggestions(amount, percentages = [15, 18, 20, 25])
        logger.info "=== Calculating tip suggestions for amount #{amount} ==="

        suggestions = {}

        percentages.each do |percentage|
          tip_amount = (amount * percentage / 100.0).round
          total_amount = amount + tip_amount

          suggestions[percentage] = {
            "percentage" => percentage,
            "tipAmount" => tip_amount,
            "totalAmount" => total_amount
          }
        end

        suggestions
      end

      def generate_tip_report(start_date = nil, end_date = nil)
        logger.info "=== Generating tip report ==="

        # Default to current month if dates not provided
        start_date ||= Date.today.beginning_of_month

        end_date ||= Date.today

        start_timestamp = DateTime.parse(start_date.to_s).to_time.to_i * 1000
        end_timestamp = DateTime.parse(end_date.to_s).to_time.to_i * 1000

        filter = "tipAmount>0 AND createdTime>=#{start_timestamp} AND createdTime<=#{end_timestamp}"

        payments = make_request(:get, endpoint("payments"), nil, { filter: filter, limit: 1000 })

        unless payments && payments["elements"]
          logger.error "Failed to retrieve payments for tip report"
          return nil
        end

        # Initialize report data
        report = {
          "startDate" => start_date.to_s,
          "endDate" => end_date.to_s,
          "totalTips" => 0,
          "tipCount" => 0,
          "averageTip" => 0,
          "averageTipPercentage" => 0,
          "tipsByEmployee" => {},
          "tipsByDay" => {},
          "tipsByHour" => {}
        }

        total_tip_percentage = 0

        payments["elements"].each do |payment|
          next unless payment["tipAmount"] && payment["tipAmount"] > 0

          tip_amount = payment["tipAmount"]
          payment_amount = payment["amount"] - tip_amount

          # Skip if payment amount is zero to avoid division by zero
          next if payment_amount == 0

          tip_percentage = (tip_amount.to_f / payment_amount * 100).round(2)

          # Increment totals
          report["totalTips"] += tip_amount
          report["tipCount"] += 1
          total_tip_percentage += tip_percentage

          # Process employee data
          if payment["employee"] && payment["employee"]["id"]
            employee_id = payment["employee"]["id"]
            employee_name = payment["employee"]["name"] || "Employee #{employee_id}"

            report["tipsByEmployee"][employee_id] ||= {
              "name" => employee_name,
              "totalTips" => 0,
              "tipCount" => 0,
              "averageTip" => 0
            }

            report["tipsByEmployee"][employee_id]["totalTips"] += tip_amount
            report["tipsByEmployee"][employee_id]["tipCount"] += 1
          end

          # Process day and hour data
          next unless payment["createdTime"]

          payment_time = Time.at(payment["createdTime"] / 1000)
          day_key = payment_time.strftime("%Y-%m-%d")
          hour_key = payment_time.strftime("%H")

          report["tipsByDay"][day_key] ||= {
            "totalTips" => 0,
            "tipCount" => 0,
            "averageTip" => 0
          }

          report["tipsByHour"][hour_key] ||= {
            "totalTips" => 0,
            "tipCount" => 0,
            "averageTip" => 0
          }

          report["tipsByDay"][day_key]["totalTips"] += tip_amount
          report["tipsByDay"][day_key]["tipCount"] += 1

          report["tipsByHour"][hour_key]["totalTips"] += tip_amount
          report["tipsByHour"][hour_key]["tipCount"] += 1
        end

        # Calculate averages
        if report["tipCount"] > 0
          report["averageTip"] = (report["totalTips"].to_f / report["tipCount"]).round(2)
          report["averageTipPercentage"] = (total_tip_percentage / report["tipCount"]).round(2)

          # Calculate employee averages
          report["tipsByEmployee"].each do |_, employee_data|
            if employee_data["tipCount"] > 0
              employee_data["averageTip"] = (employee_data["totalTips"].to_f / employee_data["tipCount"]).round(2)
            end
          end

          # Calculate day averages
          report["tipsByDay"].each do |_, day_data|
            if day_data["tipCount"] > 0
              day_data["averageTip"] = (day_data["totalTips"].to_f / day_data["tipCount"]).round(2)
            end
          end

          # Calculate hour averages
          report["tipsByHour"].each do |_, hour_data|
            if hour_data["tipCount"] > 0
              hour_data["averageTip"] = (hour_data["totalTips"].to_f / hour_data["tipCount"]).round(2)
            end
          end
        end

        report
      end

      def add_automatic_gratuity(order_id, percentage = 18, min_party_size = 6)
        logger.info "=== Adding automatic gratuity to order #{order_id} ==="

        # Check if gratuity has already been added
        order_service = OrderService.new(@config)
        service_charges = order_service.get_service_charges(order_id)

        if service_charges && service_charges["elements"]
          gratuity_charge = service_charges["elements"].find { |sc| sc["name"] && sc["name"].include?("Gratuity") }
          if gratuity_charge
            logger.info "Automatic gratuity already added to order #{order_id}, skipping"
            return gratuity_charge
          end
        end

        # Get the order
        order = order_service.get_order(order_id)

        return false unless order

        # Check if this is a large party
        customer_count = order["customerCount"] || 0

        if customer_count < min_party_size
          logger.info "Order has #{customer_count} customers, which is less than the minimum of #{min_party_size} for automatic gratuity"
          return false
        end

        # Calculate order subtotal
        subtotal = 0

        if order["lineItems"] && order["lineItems"]["elements"]
          order["lineItems"]["elements"].each do |line_item|
            subtotal += line_item["price"] * line_item["quantity"]
          end
        end

        # Calculate gratuity amount
        gratuity_amount = (subtotal * percentage / 100.0).round

        # Add as a service charge
        service_charge_data = {
          "name" => "#{percentage}% Gratuity (Party of #{customer_count})",
          "amount" => gratuity_amount,
          "taxable" => false,
          "percentage" => percentage
        }

        logger.info "Adding gratuity service charge: #{service_charge_data.inspect}"
        order_service.add_service_charge(order_id, service_charge_data)
      end

      def split_tip_among_employees(payment_id, employee_ids, distribution = nil)
        logger.info "=== Splitting tip for payment #{payment_id} among #{employee_ids.length} employees ==="

        # Check if tip has already been split
        payment = get_payment(payment_id)
        if payment && payment["tipDistributions"] && payment["tipDistributions"]["elements"] &&
           payment["tipDistributions"]["elements"].length == employee_ids.length
          logger.info "Tip for payment #{payment_id} has already been split, skipping"
          return payment["tipDistributions"]["elements"]
        end

        # Get the payment
        payment ||= make_request(:get, endpoint("payments/#{payment_id}"))

        return false unless payment && payment["tipAmount"]

        tip_amount = payment["tipAmount"]

        if tip_amount <= 0
          logger.error "Payment #{payment_id} has no tip to split"
          return false
        end

        # Determine distribution
        amounts = []

        if distribution
          # Use provided distribution
          total_distribution = distribution.sum

          employee_ids.each_with_index do |employee_id, index|
            percentage = distribution[index] / total_distribution.to_f
            amounts << (tip_amount * percentage).round
          end

          # Adjust for rounding errors
          adjustment = tip_amount - amounts.sum
          amounts[0] += adjustment
        else
          # Equal distribution
          base_amount = tip_amount / employee_ids.length
          remainder = tip_amount % employee_ids.length

          employee_ids.length.times do |i|
            amounts << if i < remainder
                         base_amount + 1
                       else
                         base_amount
                       end
          end
        end

        # Record tip distributions
        distributions = []

        employee_ids.each_with_index do |employee_id, index|
          next if amounts[index] <= 0

          # Create a record of this tip distribution
          distribution = make_request(:post, endpoint("tip_distributions"), {
                                        "payment" => { "id" => payment_id },
                                        "employee" => { "id" => employee_id },
                                        "amount" => amounts[index],
                                        "note" => "Split tip (#{index + 1}/#{employee_ids.length})"
                                      })

          distributions << distribution if distribution
        end

        distributions
      end

      private

      def get_payment(payment_id)
        logger.info "=== Fetching payment #{payment_id} ==="
        make_request(:get, endpoint("payments/#{payment_id}"))
      end
    end
  end
end
