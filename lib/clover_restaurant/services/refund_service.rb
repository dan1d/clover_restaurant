# lib/clover_restaurant/services/refund_service.rb
module CloverRestaurant
  module Services
    class RefundService < BaseService
      def get_refunds(limit = 100, offset = 0)
        logger.info "=== Fetching refunds for merchant #{@config.merchant_id} ==="
        make_request(:get, endpoint("refunds"), nil, { limit: limit, offset: offset })
      end

      def get_refund(refund_id)
        logger.info "=== Fetching refund #{refund_id} for merchant #{@config.merchant_id} ==="
        make_request(:get, endpoint("refunds/#{refund_id}"))
      end

      def get_payment_refunds(payment_id)
        logger.info "=== Fetching refunds for payment #{payment_id} ==="
        make_request(:get, endpoint("payments/#{payment_id}/refunds"))
      end

      def create_refund(payment_id, refund_data)
        logger.info "=== Creating refund for payment #{payment_id} ==="

        # Check if a similar refund already exists
        existing_refunds = get_payment_refunds(payment_id)
        if existing_refunds && existing_refunds["elements"] && refund_data["amount"] && existing_refunds["elements"].any? do |r|
          r["amount"] == refund_data["amount"]
        end
          logger.info "Refund with amount #{refund_data["amount"]} already exists for payment #{payment_id}, skipping"
          return existing_refunds["elements"].find { |r| r["amount"] == refund_data["amount"] }
        end

        logger.info "Refund data: #{refund_data.inspect}"
        make_request(:post, endpoint("payments/#{payment_id}/refunds"), refund_data)
      end

      def full_refund(payment_id, reason = nil)
        logger.info "=== Processing full refund for payment #{payment_id} ==="

        # Check if this payment has already been fully refunded
        existing_refunds = get_payment_refunds(payment_id)
        if existing_refunds && existing_refunds["elements"]
          payment = make_request(:get, endpoint("payments/#{payment_id}"))

          # Check if a refund exists with the same amount as the payment
          if payment && payment["amount"] && existing_refunds["elements"].any? { |r| r["amount"] == payment["amount"] }
            logger.info "Payment #{payment_id} has already been fully refunded, skipping"
            return existing_refunds["elements"].find { |r| r["amount"] == payment["amount"] }
          end
        end

        # Get the payment first
        payment = make_request(:get, endpoint("payments/#{payment_id}"))

        return false unless payment && payment["amount"]

        refund_data = {
          "amount" => payment["amount"]
        }

        refund_data["reason"] = reason if reason

        logger.info "Full refund data: #{refund_data.inspect}"
        create_refund(payment_id, refund_data)
      end

      def partial_refund(payment_id, amount, reason = nil)
        logger.info "=== Processing partial refund of #{amount} for payment #{payment_id} ==="

        # Check if this partial refund already exists
        existing_refunds = get_payment_refunds(payment_id)
        if existing_refunds && existing_refunds["elements"] && existing_refunds["elements"].any? do |r|
          r["amount"] == amount.to_i
        end
          logger.info "Partial refund of #{amount} already exists for payment #{payment_id}, skipping"
          return existing_refunds["elements"].find { |r| r["amount"] == amount.to_i }
        end

        refund_data = {
          "amount" => amount.to_i
        }

        refund_data["reason"] = reason if reason

        logger.info "Partial refund data: #{refund_data.inspect}"
        create_refund(payment_id, refund_data)
      end

      def refund_line_item(payment_id, line_item_id)
        logger.info "=== Refunding line item #{line_item_id} from payment #{payment_id} ==="

        # Get the payment
        payment = make_request(:get, endpoint("payments/#{payment_id}"))

        return false unless payment && payment["order"] && payment["order"]["id"]

        order_id = payment["order"]["id"]

        # Get the line item
        order_service = OrderService.new(@config)
        line_items = order_service.get_line_items(order_id)

        return false unless line_items && line_items["elements"]

        line_item = line_items["elements"].find { |item| item["id"] == line_item_id }

        return false unless line_item

        # Calculate line item total
        line_item_total = line_item["price"] * line_item["quantity"]

        # Check if refund for this line item already exists
        existing_refunds = get_payment_refunds(payment_id)
        if existing_refunds && existing_refunds["elements"] && existing_refunds["elements"].any? do |r|
          r["amount"] == line_item_total
        end
          logger.info "Refund for line item #{line_item_id} (amount #{line_item_total}) already exists, skipping"
          return existing_refunds["elements"].find { |r| r["amount"] == line_item_total }
        end

        # Refund this amount
        refund_data = {
          "amount" => line_item_total,
          "reason" => "Refund for item: #{line_item["name"]}"
        }

        logger.info "Line item refund data: #{refund_data.inspect}"
        create_refund(payment_id, refund_data)
      end

      def void_payment(payment_id, reason = "Payment voided")
        logger.info "=== Voiding payment #{payment_id} ==="

        # Check if payment is already voided
        payment = make_request(:get, endpoint("payments/#{payment_id}"))
        if payment && payment["voided"]
          logger.info "Payment #{payment_id} is already voided, skipping"
          return payment
        end

        make_request(:post, endpoint("payments/#{payment_id}"), {
                       "voided" => true,
                       "voidReason" => reason
                     })
      end

      def get_refund_reasons
        logger.info "=== Fetching standard refund reasons ==="

        [
          "Customer dissatisfied",
          "Order error",
          "Food quality issue",
          "Incorrect charge",
          "Duplicate charge",
          "Service issue",
          "Item out of stock",
          "Customer changed mind",
          "Manager authorization",
          "Other"
        ]
      end

      def generate_refund_report(start_date = nil, end_date = nil)
        logger.info "=== Generating refund report ==="

        # Default to current month if dates not provided
        start_date ||= Date.today.beginning_of_month

        end_date ||= Date.today

        start_timestamp = DateTime.parse(start_date.to_s).to_time.to_i * 1000
        end_timestamp = DateTime.parse(end_date.to_s).to_time.to_i * 1000

        filter = "createdTime>=#{start_timestamp} AND createdTime<=#{end_timestamp}"

        refunds = make_request(:get, endpoint("refunds"), nil, { filter: filter, limit: 1000 })

        unless refunds && refunds["elements"]
          logger.error "Failed to retrieve refunds for report"
          return nil
        end

        # Initialize report data
        report = {
          "startDate" => start_date.to_s,
          "endDate" => end_date.to_s,
          "totalRefunds" => 0,
          "refundCount" => refunds["elements"].length,
          "averageRefund" => 0,
          "refundsByReason" => {},
          "refundsByEmployee" => {},
          "refundsByDay" => {}
        }

        refunds["elements"].each do |refund|
          next unless refund["amount"]

          refund_amount = refund["amount"]

          # Increment total
          report["totalRefunds"] += refund_amount

          # Process reason data
          reason = refund["reason"] || "No reason provided"
          report["refundsByReason"][reason] ||= {
            "totalAmount" => 0,
            "count" => 0
          }

          report["refundsByReason"][reason]["totalAmount"] += refund_amount
          report["refundsByReason"][reason]["count"] += 1

          # Process employee data
          if refund["employee"] && refund["employee"]["id"]
            employee_id = refund["employee"]["id"]
            employee_name = refund["employee"]["name"] || "Employee #{employee_id}"

            report["refundsByEmployee"][employee_id] ||= {
              "name" => employee_name,
              "totalAmount" => 0,
              "count" => 0
            }

            report["refundsByEmployee"][employee_id]["totalAmount"] += refund_amount
            report["refundsByEmployee"][employee_id]["count"] += 1
          end

          # Process day data
          next unless refund["createdTime"]

          refund_time = Time.at(refund["createdTime"] / 1000)
          day_key = refund_time.strftime("%Y-%m-%d")

          report["refundsByDay"][day_key] ||= {
            "totalAmount" => 0,
            "count" => 0
          }

          report["refundsByDay"][day_key]["totalAmount"] += refund_amount
          report["refundsByDay"][day_key]["count"] += 1
        end

        # Calculate average
        if report["refundCount"] > 0
          report["averageRefund"] = (report["totalRefunds"].to_f / report["refundCount"]).round(2)
        end

        report
      end

      def process_return(order_id, line_item_ids = [], reason = nil, employee_id = nil)
        logger.info "=== Processing return for order #{order_id} ==="

        # Get the order
        order_service = OrderService.new(@config)
        order = order_service.get_order(order_id)

        return false unless order

        # Get payments for this order
        payments = make_request(:get, endpoint("orders/#{order_id}/payments"))

        unless payments && payments["elements"] && !payments["elements"].empty?
          logger.error "No payments found for order #{order_id}"
          return false
        end

        payment = payments["elements"].first
        payment_id = payment["id"]

        # Check if return has already been processed
        existing_refunds = get_payment_refunds(payment_id)
        if existing_refunds && existing_refunds["elements"] && !existing_refunds["elements"].empty?
          logger.info "Return has already been processed for order #{order_id}, skipping"
          return existing_refunds["elements"].first
        end

        # If line_item_ids is empty, refund the entire payment
        return full_refund(payment_id, reason) if line_item_ids.empty?

        # Otherwise, calculate the total for the specified line items
        return_amount = 0

        line_items = order_service.get_line_items(order_id)

        return false unless line_items && line_items["elements"]

        line_item_ids.each do |line_item_id|
          line_item = line_items["elements"].find { |item| item["id"] == line_item_id }

          if line_item
            line_item_total = line_item["price"] * line_item["quantity"]
            return_amount += line_item_total
          end
        end

        if return_amount <= 0
          logger.error "Invalid return amount: #{return_amount}"
          return false
        end

        # Process partial refund
        refund_data = {
          "amount" => return_amount
        }

        refund_data["reason"] = reason if reason
        refund_data["employee"] = { "id" => employee_id } if employee_id

        logger.info "Return refund data: #{refund_data.inspect}"
        create_refund(payment_id, refund_data)
      end
    end
  end
end
