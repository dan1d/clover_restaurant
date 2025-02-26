# lib/clover_restaurant/services/payment_service.rb
module CloverRestaurant
  module Services
    class PaymentService < BaseService
      def get_payments(limit = 50, offset = 0)
        logger.info "Fetching payments for merchant #{@config.merchant_id}"
        make_request(:get, endpoint("payments"), nil, { limit: limit, offset: offset })
      end

      def get_payment(payment_id)
        logger.info "Fetching payment #{payment_id} for merchant #{@config.merchant_id}"
        make_request(:get, endpoint("payments/#{payment_id}"))
      end

      def get_payments_for_order(order_id)
        logger.info "Fetching payments for order #{order_id}"
        make_request(:get, endpoint("orders/#{order_id}/payments"))
      end

      def process_payment(order_id, amount, card_details)
        logger.info "Processing payment for order #{order_id} with amount #{amount}"
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

        make_request(:post, v2_endpoint("pay"), payment_data)
      end

      def void_payment(payment_id, reason = "Payment voided")
        logger.info "Voiding payment #{payment_id}"
        make_request(:post, endpoint("payments/#{payment_id}"), {
                       "voided" => true,
                       "voidReason" => reason
                     })
      end

      def add_tip(payment_id, tip_amount)
        logger.info "Adding tip of #{tip_amount} to payment #{payment_id}"
        make_request(:post, endpoint("payments/#{payment_id}"), {
                       "tipAmount" => tip_amount.to_i
                     })
      end

      def adjust_tip(payment_id, tip_amount)
        logger.info "Adjusting tip to #{tip_amount} for payment #{payment_id}"
        make_request(:post, endpoint("payments/#{payment_id}/tip"), {
                       "tipAmount" => tip_amount.to_i
                     })
      end

      def create_refund(payment_id, refund_data)
        logger.info "Creating refund for payment #{payment_id}"
        make_request(:post, endpoint("payments/#{payment_id}/refunds"), refund_data)
      end

      def get_refunds(payment_id)
        logger.info "Fetching refunds for payment #{payment_id}"
        make_request(:get, endpoint("payments/#{payment_id}/refunds"))
      end

      def get_refund(payment_id, refund_id)
        logger.info "Fetching refund #{refund_id} for payment #{payment_id}"
        make_request(:get, endpoint("payments/#{payment_id}/refunds/#{refund_id}"))
      end

      def create_credit(amount, credit_data)
        logger.info "Creating credit for amount #{amount}"
        credit_data["amount"] = amount.to_i
        make_request(:post, endpoint("credits"), credit_data)
      end

      def simulate_card_payment(order_id, amount, options = {})
        logger.info "Simulating card payment for order #{order_id} with amount #{amount}"

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
        logger.info "Simulating cash payment for order #{order_id} with amount #{amount}"

        payment_data = {
          "order" => { "id" => order_id },
          "amount" => amount.to_i,
          "offline" => true,
          "paymentType" => "cash"
        }

        # Add employee if provided
        payment_data["employee"] = { "id" => options[:employee_id] } if options[:employee_id]

        make_request(:post, endpoint("payments"), payment_data)
      end

      def get_cash_events(limit = 50, offset = 0)
        logger.info "Fetching cash events for merchant #{@config.merchant_id}"
        make_request(:get, endpoint("cash_events"), nil, { limit: limit, offset: offset })
      end

      def create_cash_event(cash_event_data)
        logger.info "Creating cash event"
        make_request(:post, endpoint("cash_events"), cash_event_data)
      end

      def record_cash_drop(employee_id, amount, note = nil)
        logger.info "Recording cash drop of #{amount} for employee #{employee_id}"

        cash_event_data = {
          "type" => "DROP",
          "employee" => { "id" => employee_id },
          "amounts" => [{ "amount" => amount.to_i }]
        }

        cash_event_data["note"] = note if note

        create_cash_event(cash_event_data)
      end

      def record_paid_in(employee_id, amount, reason)
        logger.info "Recording paid-in of #{amount} for employee #{employee_id}"

        cash_event_data = {
          "type" => "PAID_IN",
          "employee" => { "id" => employee_id },
          "amounts" => [{ "amount" => amount.to_i }],
          "note" => reason
        }

        create_cash_event(cash_event_data)
      end

      def record_paid_out(employee_id, amount, reason)
        logger.info "Recording paid-out of #{amount} for employee #{employee_id}"

        cash_event_data = {
          "type" => "PAID_OUT",
          "employee" => { "id" => employee_id },
          "amounts" => [{ "amount" => amount.to_i }],
          "note" => reason
        }

        create_cash_event(cash_event_data)
      end
    end
  end
end
