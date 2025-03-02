module CloverRestaurant
  class PaymentEncryptor
    attr_reader :logger

    def initialize(logger = nil)
      # ✅ Ensure logger is never nil
      @logger = logger || CloverRestaurant.configuration.logger
      @payment_keys = nil

      if @payment_keys
        @modulus = @payment_keys[:modulus]
        @exponent = @payment_keys[:exponent]
        @prefix = @payment_keys[:prefix]
        @rsa_key = generate_rsa_public_key
      else
        @logger.error "❌ Payment keys are missing, encryption will not work!"
      end
    end

    def encrypt_card(card_number)
      unless @rsa_key
        @logger.error "❌ Encryption Error: RSA Key is not generated."
        return nil
      end

      begin
        cipher = OpenSSL::PKey::RSA.new(@rsa_key)
        encrypted = cipher.public_encrypt(@prefix + card_number, OpenSSL::PKey::RSA::PKCS1_OAEP_PADDING)
        Base64.strict_encode64(encrypted)
      rescue StandardError => e
        @logger.error "❌ Card Encryption Error: #{e.message}"
        nil
      end
    end

    def prepare_payment_data(order_id, amount, card_details)
      card_number = card_details[:card_number]
      encrypted_card = encrypt_card(card_number)

      unless encrypted_card
        @logger.error "❌ Failed to encrypt card data"
        return nil
      end

      {
        "orderId" => order_id,
        "currency" => "usd",
        "amount" => amount.to_i,
        "expMonth" => card_details[:exp_month],
        "cvv" => card_details[:cvv],
        "expYear" => card_details[:exp_year],
        "cardEncrypted" => encrypted_card,
        "last4" => card_number[-4..-1],
        "first6" => card_number[0..5]
      }
    end

    private

    def generate_rsa_public_key
      if @modulus.nil? || @exponent.nil?
        @logger.error "❌ RSA Key Generation Error: Modulus or Exponent is missing!"
        return nil
      end

      @logger.debug "🔐 Generating RSA public key"

      begin
        modulus_bn = OpenSSL::BN.new(@modulus, 10)
        exponent_bn = OpenSSL::BN.new(@exponent, 10)

        sequence = OpenSSL::ASN1::Sequence([
                                             OpenSSL::ASN1::Integer(modulus_bn),
                                             OpenSSL::ASN1::Integer(exponent_bn)
                                           ])

        OpenSSL::PKey::RSA.new(sequence.to_der)
      rescue StandardError => e
        @logger.error "❌ RSA Key Generation Error: #{e.message}"
        nil
      end
    end
  end
end
