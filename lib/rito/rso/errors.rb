# frozen_string_literal: true

module Rito
  module RSO
    class Error < Rito::Error; end

    class OAuthError < Error
      attr_reader :error_code, :error_description

      def initialize(message = nil, error_code: nil, error_description: nil, response: nil)
        @error_code = error_code
        @error_description = error_description
        super(message, response: response)
      end
    end

    class InvalidToken < Error; end
  end
end
