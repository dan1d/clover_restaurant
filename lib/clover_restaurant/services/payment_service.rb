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

        # The incoming total_amount from the simulator is (subtotal_after_discount + tip_amount)
        # We need to isolate the subtotal_after_discount for the 'amount' field.
        subtotal_after_discount = total_amount - tip_amount

        # Construct payment payload
        payment_data = {
          "order" => { "id" => order_id },
          "tender" => { "id" => selected_tender["id"] },
          "employee" => { "id" => employee_id },
          "offline" => false,
          "amount" => subtotal_after_discount, # This should be the order subtotal (after discounts, before tax and tip)
          "tipAmount" => tip_amount,
          "taxAmount" => tax_amount,
          "createdTime" => past_timestamp, # Use past timestamp
          "clientCreatedTime" => past_timestamp, # Use past timestamp
          "modifiedTime" => past_timestamp, # Use past timestamp
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

        logger.info "Detailed Payment Payload for Order ID #{order_id}:"
        logger.info "  Original total_amount (total_after_discount + tip_amount from simulator): #{total_amount}"
        logger.info "  Calculated tax_amount: #{tax_amount}"
        logger.info "  Calculated tip_amount: #{tip_amount}"
        logger.info "  Payload 'amount' (subtotal_after_discount): #{payment_data["amount"]}"
        logger.info "  Payload 'tipAmount': #{payment_data["tipAmount"]}"
        logger.info "  Payload 'taxAmount': #{payment_data["taxAmount"]}"
        logger.info "  Payload 'tender_id': #{selected_tender["id"]}"
        logger.info "  Payload 'employee_id': #{employee_id}"
        logger.info "  Payload JSON: #{payment_data.to_json}" # Log the whole payload

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

      def create_refund(payment_id, order_id, amount, reason = "MANUAL_REFUND")
        logger.info "🔄 Processing refund for Payment ID: #{payment_id}, Order ID: #{order_id}, Amount: $#{amount / 100.0}"

        unless payment_id && order_id && amount && amount > 0
          logger.error "❌ Invalid parameters for refund. Payment ID, Order ID, and positive amount are required."
          return nil
        end

        payload = {
          "amount" => amount,
          "orderRef" => { "id" => order_id },
          # "reason" => reason # The API might have specific allowed values or handle it differently.
          # For a full refund against a payment, often just amount and paymentID are needed for the endpoint.
          # The endpoint is /v3/merchants/{mId}/payments/{paymentId}/refunds
          # The payload for this specific endpoint might only need "amount", and sometimes "fullRefund": true/false
          # Let's simplify the payload for this specific endpoint first.
          # If it's a full refund, usually no amount is needed, or "fullRefund": true
          # If partial, amount is needed.
        }

        # Based on typical Clover refund APIs for a specific payment:
        # POST /v3/merchants/{mId}/payments/{paymentId}/refunds
        # Payload: { "amount": <amount_in_cents> } for partial, or { "fullRefund": true } for full.
        # Let's assume we are doing a partial refund with a specific amount for now.
        # The `orderRef` is usually not needed if refunding a specific payment directly.
        # If the API requires orderRef even for payment-specific refund, we keep it.
        # The provided payload structure might be for a generic refund not tied to a specific payment.
        # Let's adjust to what POST /payments/{paymentId}/refunds usually expects:

        actual_payload = {
          "amount" => amount
          # "orderRef": { "id": order_id } # Keep if API docs for this specific path confirm it.
          # "reason": reason # Keep if API docs for this specific path confirm it.
        }
        # If it's intended to be a full refund, and API supports it, one might send: actual_payload = { "fullRefund": true }


        logger.info "Refund payload for payment '#{payment_id}': #{actual_payload.inspect}"
        response = make_request(:post, endpoint("payments/#{payment_id}/refunds"), actual_payload)

        if response && response["id"]
          logger.info "✅ Refund Successful: #{response["id"]}. Amount: $#{response.dig("amount") / 100.0}"
          response
        else
          logger.error "❌ Refund Failed for payment '#{payment_id}'. Response: #{response.inspect}"
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
