# frozen_string_literal: true

module Rito
  module RSO
    class Credential
      ASSERTION_TTL = 300

      def initialize(client_secret: nil, client_assertion: nil, private_key: nil)
        provided = [client_secret, client_assertion, private_key].count { |value| value && !value.to_s.empty? }
        raise ConfigError, 'provide only one of client_secret, client_assertion, or private_key' if provided > 1

        @client_secret = client_secret
        @client_assertion = client_assertion
        @private_key = normalize_key(private_key)
      end

      def configured?
        @client_secret || @client_assertion || @private_key
      end

      def basic?
        !!@client_secret
      end

      def authorization_header(client_id)
        "Basic #{["#{client_id}:#{@client_secret}"].pack('m0')}"
      end

      def token_params(params, client_id:, aud:)
        unless configured?
          raise ConfigError,
                'client_secret, client_assertion, or private_key is required for token requests'
        end

        return params if @client_secret

        params.merge(
          client_assertion_type: JWT_BEARER_TYPE,
          client_assertion: @client_assertion || mint_assertion(client_id, aud)
        )
      end

      private

      def mint_assertion(client_id, aud)
        now = Time.now.to_i
        Jwt.sign_rs256(
          {
            'iss' => client_id,
            'sub' => client_id,
            'aud' => aud,
            'exp' => now + ASSERTION_TTL,
            'iat' => now,
            'jti' => SecureRandom.uuid
          },
          @private_key
        )
      end

      def normalize_key(key)
        return nil if key.nil? || key.to_s.empty?
        return key if key.is_a?(OpenSSL::PKey::RSA)

        OpenSSL::PKey::RSA.new(key)
      rescue OpenSSL::PKey::PKeyError, ArgumentError
        raise ConfigError, 'private_key is not a valid RSA key'
      end
    end
  end
end
