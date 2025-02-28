# lib/clover_restaurant/services/payment_service.rb
module CloverRestaurant
  module Services
    class PaymentService < BaseService
      def get_payments(limit = 50, offset = 0)
        logger.info "=== Fetching payments for merchant #{@config.merchant_id} ==="
        make_request(:get, endpoint("payments"), nil, { limit: limit, offset: offset })
      end

      def get_payment(payment_id)
        logger.info "=== Fetching payment #{payment_id} for merchant #{@config.merchant_id} ==="
        make_request(:get, endpoint("payments/#{payment_id}"))
      end

      def get_payments_for_order(order_id)
        logger.info "=== Fetching payments for order #{order_id} ==="
        make_request(:get, endpoint("orders/#{order_id}/payments"))
      end

      def process_payment(order_id, amount, card_details)
        logger.info "=== Processing payment for order #{order_id} with amount #{amount} ==="

        # Check if payment already exists for this order
        existing_payments = get_payments_for_order(order_id)
        if existing_payments && existing_payments["elements"] && !existing_payments["elements"].empty?
          existing_payment = existing_payments["elements"].find { |p| p["amount"] == amount }
          if existing_payment
            logger.info "Payment of #{amount} already exists for order #{order_id}, skipping"
            return existing_payment
          end
        end

        merchant_service = MerchantService.new(@config)
        pay_key = merchant_service.get_payment_key

        unless pay_key && pay_key["modulus"] && pay_key["exponent"] && pay_key["prefix"]
          logger.error "Failed to retrieve payment key"
          return nil
        end

        encryptor = PaymentEncryptor.new({
                                           modulus: pay_key["modulus"].to_i,
                                           exponent: pay_key["exponent"].to_i,
                                           prefix: pay_key["prefix"].to_s
                                         }, logger)

        payment_data = encryptor.prepare_payment_data(order_id, amount, card_details)

        unless payment_data
          logger.error "Failed to prepare payment data"
          return nil
        end

        logger.info "Payment data prepared (sensitive data not logged)"
        make_request(:post, v2_endpoint("pay"), payment_data)
      end

      def void_payment(payment_id, reason = "Payment voided")
        logger.info "=== Voiding payment #{payment_id} ==="

        # Check if payment is already voided
        payment = get_payment(payment_id)
        if payment && payment["voided"]
          logger.info "Payment #{payment_id} is already voided, skipping"
          return payment
        end

        make_request(:post, endpoint("payments/#{payment_id}"), {
                       "voided" => true,
                       "voidReason" => reason
                     })
      end

      def add_tip(payment_id, tip_amount)
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

      def create_refund(payment_id, refund_data)
        logger.info "=== Creating refund for payment #{payment_id} ==="

        # Check if a similar refund already exists
        existing_refunds = get_refunds(payment_id)
        if existing_refunds && existing_refunds["elements"] && refund_data["amount"] && existing_refunds["elements"].any? do |r|
          r["amount"] == refund_data["amount"]
        end
          logger.info "Refund with amount #{refund_data["amount"]} already exists for payment #{payment_id}, skipping"
          return existing_refunds["elements"].find { |r| r["amount"] == refund_data["amount"] }
        end

        logger.info "Refund data: #{refund_data.inspect}"
        make_request(:post, endpoint("payments/#{payment_id}/refunds"), refund_data)
      end

      def get_refunds(payment_id)
        logger.info "=== Fetching refunds for payment #{payment_id} ==="
        make_request(:get, endpoint("payments/#{payment_id}/refunds"))
      end

      def get_refund(payment_id, refund_id)
        logger.info "=== Fetching refund #{refund_id} for payment #{payment_id} ==="
        make_request(:get, endpoint("payments/#{payment_id}/refunds/#{refund_id}"))
      end

      def create_credit(amount, credit_data)
        logger.info "=== Creating credit for amount #{amount} ==="
        credit_data["amount"] = amount.to_i
        logger.info "Credit data: #{credit_data.inspect}"
        make_request(:post, endpoint("credits"), credit_data)
      end

      def simulate_card_payment(order_id, amount, options = {})
        logger.info "=== Simulating card payment for order #{order_id} with amount #{amount} ==="

        # Check if payment already exists for this order
        existing_payments = get_payments_for_order(order_id)
        if existing_payments && existing_payments["elements"] && !existing_payments["elements"].empty?
          logger.info "Payment already exists for order #{order_id}, skipping"
          return existing_payments["elements"].first
        end

        # Default credit card details if not provided
        card_details = options[:card_details] || {
          card_number: "6011361000006668", # Test Discover card
          exp_month: 12,
          exp_year: (Time.now.year + 1),
          cvv: "123"
        }

        process_payment(order_id, amount, card_details)
      end

      def simulate_cash_payment(order_id, amount, options = {})
        logger.info "=== Simulating cash payment for order #{order_id} with amount #{amount} ==="

        # Check if payment already exists for this order
        existing_payments = get_payments_for_order(order_id)
        if existing_payments && existing_payments["elements"] && !existing_payments["elements"].empty?
          logger.info "Payment already exists for order #{order_id}, skipping"
          return existing_payments["elements"].first
        end

        payment_data = {
          "order" => { "id" => order_id },
          "amount" => amount.to_i,
          "offline" => true,
          "paymentType" => "cash"
        }

        # Add employee if provided
        payment_data["employee"] = { "id" => options[:employee_id] } if options[:employee_id]

        logger.info "Payment data: #{payment_data.inspect}"
        make_request(:post, endpoint("payments"), payment_data)
      end

      def get_cash_events(limit = 50, offset = 0)
        logger.info "=== Fetching cash events for merchant #{@config.merchant_id} ==="
        make_request(:get, endpoint("cash_events"), nil, { limit: limit, offset: offset })
      end

      def create_cash_event(cash_event_data)
        logger.info "=== Creating cash event ==="
        logger.info "Cash event data: #{cash_event_data.inspect}"
        make_request(:post, endpoint("cash_events"), cash_event_data)
      end

      def record_cash_drop(employee_id, amount, note = nil)
        logger.info "=== Recording cash drop of #{amount} for employee #{employee_id} ==="

        cash_event_data = {
          "type" => "DROP",
          "employee" => { "id" => employee_id },
          "amounts" => [{ "amount" => amount.to_i }]
        }

        cash_event_data["note"] = note if note

        logger.info "Cash drop data: #{cash_event_data.inspect}"
        create_cash_event(cash_event_data)
      end

      def record_paid_in(employee_id, amount, reason)
        logger.info "=== Recording paid-in of #{amount} for employee #{employee_id} ==="

        cash_event_data = {
          "type" => "PAID_IN",
          "employee" => { "id" => employee_id },
          "amounts" => [{ "amount" => amount.to_i }],
          "note" => reason
        }

        logger.info "Paid-in data: #{cash_event_data.inspect}"
        create_cash_event(cash_event_data)
      end

      def record_paid_out(employee_id, amount, reason)
        logger.info "=== Recording paid-out of #{amount} for employee #{employee_id} ==="

        cash_event_data = {
          "type" => "PAID_OUT",
          "employee" => { "id" => employee_id },
          "amounts" => [{ "amount" => amount.to_i }],
          "note" => reason
        }

        logger.info "Paid-out data: #{cash_event_data.inspect}"
        create_cash_event(cash_event_data)
      end
    end
  end
end
