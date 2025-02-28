module CloverRestaurant
  module Services
    class PaymentService < BaseService
      def initialize
        super()
        @encryptor = nil
      end

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

      def encryptor
        @encryptor ||= begin
          pay_key = get_pay_key
          return nil unless pay_key

          CloverRestaurant::PaymentEncryptor.new(pay_key, logger)
        end
      end

      def create_payment(order_id, amount, card_details)
        logger.info "💳 Processing Payment for Order: #{order_id}, Amount: $#{amount / 100.0}..."

        encrypted_data = encryptor.prepare_payment_data(order_id, amount, card_details)
        return logger.error("❌ Failed to encrypt card data") unless encrypted_data

        # Add required fields for Developer Pay API
        encrypted_data["zip"] = "94041"  # Required ZIP code
        encrypted_data["taxAmount"] = 9  # Example tax amount

        response = make_request(:post, "/v2/merchant/#{@config.merchant_id}/pay", encrypted_data)

        # 🔥 FIX: Check for "result": "APPROVED", not "status"
        if response && response["result"] == "APPROVED"
          payment_id = response["paymentId"]
          logger.info "✅ Payment successful for Order: #{order_id}, Payment ID: #{payment_id}"

          # 🔥 Update the order total only if the payment is approved
          update_order_total(order_id, amount)

          response
        else
          logger.error "❌ Payment failed: #{response.inspect}"
          nil
        end
      end

      def update_order_total(order_id, total)
        logger.info "🔄 Updating order total to $#{total / 100.0} for Order: #{order_id}..."

        payload = { "total" => total }
        response = make_request(:post, "v3/merchants/#{@config.merchant_id}/orders/#{order_id}", payload)

        if response
          logger.info "✅ Order total updated successfully."
        else
          logger.error "❌ Failed to update order total."
        end
      end
    end
  end
end
