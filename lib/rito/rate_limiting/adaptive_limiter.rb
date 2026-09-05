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
        app = app_bucket(key, region)
        method = method_bucket(key, region, bucket)
        loop do
          delay = @mutex.synchronize do
            [app.delay, method.delay].max.tap do |wait|
              if wait.zero?
                app.consume!
                method.consume!
              end
            end
          end
          return if delay.zero?

          @sleeper.call(delay + 0.001)
        end
      end

      def observe!(response, key:, region:, bucket:)
        headers = response.headers
        status = response.status

        app = app_bucket(key, region)
        method = method_bucket(key, region, bucket)

        @mutex.synchronize do
          app.apply!(limits: HeaderParser.app_limits(headers), counts: HeaderParser.app_counts(headers),
                     limited: status == 429)
          method.apply!(limits: HeaderParser.method_limits(headers), counts: HeaderParser.method_counts(headers),
                        limited: status == 429)
          if status == 429
            target = HeaderParser.limit_type(headers) == :application ? app : method
            target.limit_block!(HeaderParser.retry_after(headers))
          end
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
