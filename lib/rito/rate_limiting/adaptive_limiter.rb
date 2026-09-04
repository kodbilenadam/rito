# frozen_string_literal: true

module Rito
  module RateLimiting
    # Pre-emptive limiter driven entirely by rate limit headers.
    # Buckets are keyed per (api key, region, endpoint) so multiple keys
    # and regions never share state.
    class AdaptiveLimiter
      def initialize(clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) },
                     sleeper: Kernel.method(:sleep))
        @buckets = {}
        @mutex = Mutex.new
        @clock = clock
        @sleeper = sleeper
      end

      def acquire!(key:, region:, bucket:)
        app_bucket(key, region).wait_until_allowed!
        method_bucket(key, region, bucket).wait_until_allowed!
      end

      def observe!(response, key:, region:, bucket:)
        headers = response.headers
        status = response.status

        app = app_bucket(key, region)
        method = method_bucket(key, region, bucket)

        app.apply!(limits: HeaderParser.app_limits(headers), counts: HeaderParser.app_counts(headers))
        method.apply!(limits: HeaderParser.method_limits(headers), counts: HeaderParser.method_counts(headers))

        return unless status == 429

        retry_after = HeaderParser.retry_after(headers)
        case HeaderParser.limit_type(headers)
        when :application
          app.limit_block!(retry_after)
        when :method, :service
          method.limit_block!(retry_after)
        else
          method.limit_block!(retry_after)
        end
      end

      def bucket_blocked?(key:, region:, bucket: nil, scope: :app)
        bucket_for_scope(key, region, bucket, scope).blocked?
      end

      private

      def app_bucket(key, region)
        bucket_for('app', key, region, nil)
      end

      def method_bucket(key, region, bucket)
        bucket_for('method', key, region, bucket)
      end

      def bucket_for_scope(key, region, bucket, scope)
        scope == :app ? app_bucket(key, region) : method_bucket(key, region, bucket)
      end

      def bucket_for(scope, key, region, endpoint)
        @mutex.synchronize do
          @buckets[[scope, key, Routing.normalize(region), endpoint]] ||=
            Bucket.new(clock: @clock, sleeper: @sleeper)
        end
      end
    end
  end
end
