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
        key = @client.api_key || @client.bearer_token
        retries = 0
        request_body = env.body
        begin
          limiter&.acquire!(key: key, region: region_from(env), bucket: bucket_from(env))
          env.body = request_body
          env.request.context[:attempts] += 1 if env.request.context
          @app.call(env)
        rescue Rito::RateLimited
          retries += 1
          retry if retries <= @client.max_retries
          raise
        end
      end

      private

      def region_from(env)
        env.url.host.to_s.split('.').first
      end

      def bucket_from(env)
        env.url.path.split('/').reject(&:empty?).first(2).join('/')
      end
    end
  end
end
