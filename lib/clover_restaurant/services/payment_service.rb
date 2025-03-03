module CloverRestaurant
  module Services
    class PaymentService < BaseService
      def get_pay_key
        logger.info "🔑 Fetching Clover Developer Pay Key..."

        response = make_request(:get, "/v2/merchant/#{@config.merchant_id}/pay/key")

        unless response.is_a?(Hash) && response.key?("modulus") && response.key?("exponent") && response.key?("prefix")
          logger.error "❌ Failed to fetch Developer Pay Key! Invalid response: #{response.inspect}"
          return nil
        end

        {
          modulus: response["modulus"],
          exponent: response["exponent"],
          prefix: response["prefix"]
        }
      end

      def get_payments
        logger.info "🔄 Fetching all payments..."

        response = make_request(:get, endpoint("payments"))

        if response && response["elements"] && response["elements"] != []
          logger.info "✅ Fetched #{response["elements"].size} payments."
          response["elements"]
        else
          logger.error "❌ Failed to fetch payments: #{response.inspect}"
          []
        end
      end

      def delete_all_payments
        logger.info "🚨 Deleting all payments..."

        payments = get_payments
        [payments].flatten.compact.each do |payment|
          response = make_request(:delete, endpoint("payments/#{payment["id"]}"))

          if response
            logger.info "✅ Payment deleted: #{payment["id"]}"
          else
            logger.error "❌ Failed to delete payment: #{payment["id"]}"
          end
        end
      end

      def encryptor
        @encryptor ||= begin
          pay_key = get_pay_key
          return nil unless pay_key

          CloverRestaurant::PaymentEncryptor.new(logger)
        end
      end

      def process_payment(order_id, total_amount, employee_id, past_timestamp, tip_amount = 0, tax_amount = 0)
        logger.info "💳 Processing payment for Order: #{order_id}, Amount: $#{total_amount / 100.0}..."

        # Fetch available tenders
        tenders = @services_manager.tender.get_tenders
        return logger.error("❌ No tenders available.") if tenders.empty?

        # Select a random tender
        selected_tender = tenders.sample
        logger.info "🛠 Using Tender: #{selected_tender["label"]} (ID: #{selected_tender["id"]})"

        # Ensure a valid amount
        if total_amount <= 0
          logger.error "❌ Payment amount must be positive."
          return
        end

        # Construct payment payload
        payment_data = {
          "order" => { "id" => order_id },
          "tender" => { "id" => selected_tender["id"] },
          "employee" => { "id" => employee_id },
          "offline" => false,
          "amount" => total_amount - tax_amount,
          "tipAmount" => tip_amount,
          "taxAmount" => tax_amount,
          "createdTime" => past_timestamp, # Use past timestamp
          "clientCreatedTime" => past_timestamp, # Use past timestamp
          "transactionSettings" => {
            "disableCashBack" => false,
            "cloverShouldHandleReceipts" => true,
            "forcePinEntryOnSwipe" => false,
            "disableRestartTransactionOnFailure" => false,
            "allowOfflinePayment" => false,
            "approveOfflinePaymentWithoutPrompt" => false,
            "forceOfflinePayment" => false,
            "disableReceiptSelection" => false,
            "disableDuplicateCheck" => false,
            "autoAcceptPaymentConfirmations" => false,
            "autoAcceptSignature" => false,
            "returnResultOnTransactionComplete" => false,
            "disableCreditSurcharge" => false
          },
          "transactionInfo" => {
            "isTokenBasedTx" => false,
            "emergencyFlag" => false
          }
        }

        response = make_request(:post, endpoint("orders/#{order_id}/payments"), payment_data)

        if response && response["id"]
          logger.info "✅ Payment Successful: #{response["id"]} from 1 month ago"
          update_order_total(order_id, total_amount + tip_amount)
          response
        else
          logger.error "❌ Payment Failed: #{response.inspect}"
          nil
        end
      end

      private

      def random_payment_method
        methods = %i[credit_card cash custom_tender]
        methods.sample
      end

      def process_credit_card_payment(order_id, amount)
        logger.info "💳 Paying with Credit Card for Order #{order_id}"

        card_details = {
          card_number: "4111111111111111",
          exp_month: "12",
          exp_year: "2027",
          cvv: "123"
        }

        encrypted_data = encryptor&.prepare_payment_data(order_id, amount, card_details)

        unless encrypted_data
          logger.error "❌ Failed to encrypt card data. Falling back to cash payment."
          return process_cash_payment(order_id, amount)
        end

        encrypted_data["zip"] = "94041"
        encrypted_data["taxAmount"] = 9

        response = make_request(:post, "/v2/merchant/#{@config.merchant_id}/pay", encrypted_data)

        if response && response["result"] == "APPROVED"
          logger.info "✅ Credit Card Payment Approved: #{response["paymentId"]}"
          update_order_total(order_id, amount)
        else
          logger.error "❌ Credit Card Payment Failed: #{response.inspect}"
          process_cash_payment(order_id, amount)
        end
      end

      def process_cash_payment(order_id, amount)
        logger.info "💵 Paying with Cash for Order #{order_id}"

        payment_data = {
          "orderId" => order_id,
          "amount" => amount,
          "tender" => { "id" => "CASH" }
        }

        response = make_request(:post, endpoint("payments"), payment_data)

        if response && response["id"]
          logger.info "✅ Cash Payment Successful: #{response["id"]}"
          update_order_total(order_id, amount)
        else
          logger.error "❌ Cash Payment Failed: #{response.inspect}"
        end
      end

      def process_custom_tender_payment(order_id, amount)
        logger.info "🔄 Fetching available tenders..."

        tenders = @services_manager.tender.get_tenders
        return process_cash_payment(order_id, amount) if tenders.empty?

        custom_tender = tenders.sample
        logger.info "💳 Paying with Custom Tender: #{custom_tender["label"]}"

        payment_data = {
          "orderId" => order_id,
          "amount" => amount,
          "tender" => { "id" => custom_tender["id"] }
        }

        response = make_request(:post, endpoint("payments"), payment_data)

        if response && response["id"]
          logger.info "✅ Custom Tender Payment Successful: #{response["id"]}"
          update_order_total(order_id, amount)
        else
          logger.error "❌ Custom Tender Payment Failed: #{response.inspect}"
          process_cash_payment(order_id, amount)
        end
      end

      def update_order_total(order_id, total)
        logger.info "🔄 Updating order total to $#{total / 100.0} for Order: #{order_id}..."

        payload = { "total" => total }
        response = make_request(:post, endpoint("orders/#{order_id}"), payload)

        if response
          logger.info "✅ Order total updated successfully."
        else
          logger.error "❌ Failed to update order total."
        end
      end
    end
  end
end
