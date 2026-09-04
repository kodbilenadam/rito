# frozen_string_literal: true

module Rito
  module RateLimiting
    module HeaderParser
      module_function

      def parse_pairs(value)
        return [] if value.nil?

        value.split(',').filter_map do |part|
          limit, window = part.strip.split(':', 2)
          next if limit.nil? || window.nil?

          [Integer(limit), Integer(window)]
        rescue ArgumentError
          next
        end
      end

      def app_limits(headers)
        parse_pairs(headers['X-App-Rate-Limit'])
      end

      def app_counts(headers)
        parse_pairs(headers['X-App-Rate-Limit-Count'])
      end

      def method_limits(headers)
        parse_pairs(headers['X-Method-Rate-Limit'])
      end

      def method_counts(headers)
        parse_pairs(headers['X-Method-Rate-Limit-Count'])
      end

      def retry_after(headers)
        value = headers['Retry-After']
        Integer(value) if value&.match?(/\A\d+\z/)
      end

      LIMIT_TYPES = {
        'application' => :application,
        'method' => :method,
        'service' => :service
      }.freeze

      def limit_type(headers)
        LIMIT_TYPES[headers['X-Rate-Limit-Type']]
      end
    end
  end
end
