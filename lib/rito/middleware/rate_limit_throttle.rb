# frozen_string_literal: true

module Rito
  module Middleware
    # Runs before the network call: blocks until the adaptive limiter allows
    # the request, and retries RateLimited responses until max_retries is
    # exhausted (the limiter blocks the bucket before the rescue, so the retry
    # honors Retry-After automatically). Region and endpoint bucket are derived
    # from the request URL.
    class RateLimitThrottle < Faraday::Middleware
      def initialize(app, client:)
        super(app)
        @client = client
      end

      def call(env)
        limiter = @client.limiter
        key = @client.api_key
        return @app.call(env) if limiter.nil? || key.nil?

        attempts = 0
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        begin
          limiter.acquire!(key: key, region: region_from(env), bucket: bucket_from(env))
          response = @app.call(env)
          emit(env, response.status, started, attempts)
          response
        rescue Rito::RateLimited => e
          emit(env, e.status, started, attempts, error: e.class.name)
          attempts += 1
          retry if attempts <= @client.max_retries
          raise
        end
      end

      private

      def emit(env, status, started, attempts, error: nil)
        Instrumentation.emit(
          http_method: env.method,
          url: env.url.to_s,
          status: status,
          attempts: attempts,
          duration_ms: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round(2),
          error: error
        )
      end

      def region_from(env)
        env.url.host.to_s.split('.').first
      end

      def bucket_from(env)
        env.url.path.split('/').first(2).join('/')
      end
    end
  end
end
