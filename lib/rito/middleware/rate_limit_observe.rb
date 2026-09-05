# frozen_string_literal: true

module Rito
  module Middleware
    # First response middleware: syncs limiter state from rate limit headers
    # before RiotErrors raises, so blocks are in place before any retry.
    class RateLimitObserve < Faraday::Middleware
      def initialize(app, client:)
        super(app)
        @client = client
      end

      def on_complete(env)
        limiter = @client.limiter
        key = @client.api_key || @client.bearer_token
        return if limiter.nil? || key.nil?

        limiter.observe!(Faraday::Response.new(env), key: key, region: region_from(env), bucket: bucket_from(env))
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
