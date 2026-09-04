# frozen_string_literal: true

module Rito
  module RSO
    module Jwt
      module_function

      def header(jwt)
        parse_segment(jwt, 0)
      end

      def claims(jwt)
        parse_segment(jwt, 1)
      end

      def sign_rs256(payload_claims, key, header_claims: { 'alg' => 'RS256', 'typ' => 'JWT' })
        signing_input = "#{encode(header_claims)}.#{encode(payload_claims)}"
        signature = key.sign(OpenSSL::Digest.new('SHA256'), signing_input)
        "#{signing_input}.#{base64url_encode(signature)}"
      end

      def base64url_encode(bytes)
        [bytes].pack('m0').tr('+/', '-_').sub(/=+\z/, '')
      end

      def base64url_decode(str)
        str.to_s.tr('-_', '+/').unpack1('m')
      end

      def encode(hash)
        base64url_encode(JSON.generate(hash))
      end

      def parse_segment(jwt, index)
        segments = jwt.to_s.split('.')
        segment = segments[index]
        raise InvalidToken, 'malformed JWT' if segment.to_s.empty?

        JSON.parse(base64url_decode(segment))
      rescue JSON::ParserError, ArgumentError
        raise InvalidToken, 'malformed JWT'
      end
    end
  end
end
