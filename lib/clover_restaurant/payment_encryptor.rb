module CloverRestaurant
  class PaymentEncryptor
    attr_reader :logger

    def initialize(pay_key, logger = nil)
      @modulus = pay_key[:modulus]
      @exponent = pay_key[:exponent]
      @prefix = pay_key[:prefix]
      @logger = logger || CloverRestaurant.configuration.logger
      @rsa_key = generate_rsa_public_key
    end

    def encrypt_card(card_number)
      cipher = OpenSSL::PKey::RSA.new(@rsa_key)
      encrypted = cipher.public_encrypt(@prefix + card_number, OpenSSL::PKey::RSA::PKCS1_OAEP_PADDING)
      Base64.strict_encode64(encrypted)
    rescue StandardError => e
      @logger.error "Card encryption error: #{e.message}"
      nil
    end

    def prepare_payment_data(order_id, amount, card_details)
      card_number = card_details[:card_number]
      encrypted_card = encrypt_card(card_number)

      unless encrypted_card
        @logger.error 'Failed to encrypt card data'
        return nil
      end

      {
        'orderId' => order_id,
        'currency' => 'usd',
        'amount' => amount.to_i,
        'expMonth' => card_details[:exp_month],
        'cvv' => card_details[:cvv],
        'expYear' => card_details[:exp_year],
        'cardEncrypted' => encrypted_card,
        'last4' => card_number[-4..-1],
        'first6' => card_number[0..5]
      }
    end

    private

    def generate_rsa_public_key
      @logger.debug 'Generating RSA public key'
      modulus_bn = OpenSSL::BN.new(@modulus.to_s, 10)
      exponent_bn = OpenSSL::BN.new(@exponent.to_s, 10)

      sequence = OpenSSL::ASN1::Sequence([
                                          OpenSSL::ASN1::Integer(modulus_bn),
                                          OpenSSL::ASN1::Integer(exponent_bn)
                                        ])

      OpenSSL::PKey::RSA.new(sequence.to_der)
    rescue StandardError => e
      @logger.error "RSA key generation error: #{e.message}"
      nil
    end
  end
end
