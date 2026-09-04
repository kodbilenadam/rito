# frozen_string_literal: true

module Rito
  module RSO
    module Jwks
      module_function

      def public_key(jwk)
        raise InvalidToken, "unsupported key type: #{jwk['kty'].inspect}" unless jwk['kty'] == 'RSA'

        modulus = OpenSSL::BN.new(Jwt.base64url_decode(jwk.fetch('n')), 2)
        exponent = OpenSSL::BN.new(Jwt.base64url_decode(jwk.fetch('e')), 2)
        sequence = OpenSSL::ASN1::Sequence.new(
          [OpenSSL::ASN1::Integer.new(modulus), OpenSSL::ASN1::Integer.new(exponent)]
        )
        OpenSSL::PKey::RSA.new(sequence.to_der)
      end
    end
  end
end
