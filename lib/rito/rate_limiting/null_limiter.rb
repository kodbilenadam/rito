# frozen_string_literal: true

module Rito
  module RateLimiting
    class NullLimiter
      def acquire!(key:, region:, bucket:); end

      def observe!(response, key:, region:, bucket:); end
    end
  end
end
