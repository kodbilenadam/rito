# frozen_string_literal: true

require 'digest'

module Rito
  module RateLimiting
    # Distributed rate limiter backed by Redis for multi-process / multi-host
    # applications. Soft dependency: requires the `redis` gem at instantiation,
    # not at load time.
    #
    # Fixed windows with atomic check-and-increment (Lua), counters synced from
    # authoritative X-*-Count headers, and per-scope block keys for Retry-After.
    class RedisLimiter
      class DependencyMissing < Error; end

      LIMITS_TTL = 600

      # KEYS[1] = app block key, KEYS[2] = method block key, KEYS[3..] = counters
      # ARGV = limit, window pairs matching KEYS[3..]
      ALLOW_SCRIPT = <<~LUA
        for i = 1, 2 do
          if redis.call('EXISTS', KEYS[i]) == 1 then
            return 0
          end
        end
        for i = 3, #KEYS do
          local idx = i - 3
          local limit = tonumber(ARGV[idx * 2 + 1])
          local window = tonumber(ARGV[idx * 2 + 2])
          if limit then
            local count = redis.call('INCR', KEYS[i])
            if count == 1 then
              redis.call('EXPIRE', KEYS[i], window)
            end
            if count > limit then
              redis.call('DECR', KEYS[i])
              return 0
            end
          end
        end
        return 1
      LUA

      def initialize(redis:, sleeper: Kernel.method(:sleep))
        raise DependencyMissing, 'Add the `redis` gem to your Gemfile to use RedisLimiter' unless defined?(::Redis)

        @redis = redis
        @sleeper = sleeper
      end

      def acquire!(key:, region:, bucket:)
        loop do
          return if allowed?(key, region, bucket)

          @sleeper.call(1)
        end
      end

      def observe!(response, key:, region:, bucket:)
        headers = response.headers
        status = response.status
        prefix = prefix_for(key, region)

        if status == 429
          block!(prefix, bucket, headers)
        else
          sync_limits!(prefix, bucket, headers)
          sync_counts!(prefix, bucket, headers)
        end
      end

      def blocked?(key:, region:, bucket: nil, scope: :app)
        prefix = prefix_for(key, region)
        block_key = scope == :app ? "#{prefix}:block" : "#{prefix}:m:#{bucket}:block"
        @redis.exists?(block_key)
      end

      private

      def allowed?(key, region, bucket)
        prefix = prefix_for(key, region)
        method_prefix = "#{prefix}:m:#{bucket}"

        app_limits = parse_limits(@redis.hget("#{prefix}:limits", 'app'))
        method_limits = parse_limits(@redis.hget("#{prefix}:limits", bucket))

        keys = ["#{prefix}:block", "#{method_prefix}:block"]
        argv = []
        app_limits.each do |limit, window|
          keys << "#{prefix}:app:#{window}"
          argv << limit.to_s << window.to_s
        end
        method_limits.each do |limit, window|
          keys << "#{method_prefix}:#{window}"
          argv << limit.to_s << window.to_s
        end

        @redis.eval(ALLOW_SCRIPT, keys: keys, argv: argv) == 1
      end

      def block!(prefix, bucket, headers)
        retry_after = HeaderParser.retry_after(headers) || 2
        case HeaderParser.limit_type(headers)
        when :application
          @redis.set("#{prefix}:block", '1', ex: retry_after)
        when :method, :service
          @redis.set("#{prefix}:m:#{bucket}:block", '1', ex: retry_after)
        else
          @redis.set("#{prefix}:m:#{bucket}:block", '1', ex: retry_after)
        end
      end

      def sync_limits!(prefix, bucket, headers)
        app_limits = HeaderParser.app_limits(headers)
        method_limits = HeaderParser.method_limits(headers)
        return if app_limits.empty? && method_limits.empty?

        mapping = {}
        mapping['app'] = serialize(app_limits) unless app_limits.empty?
        mapping[bucket] = serialize(method_limits) unless method_limits.empty?
        @redis.hset("#{prefix}:limits", mapping)
        @redis.expire("#{prefix}:limits", LIMITS_TTL)
      end

      def sync_counts!(prefix, bucket, headers)
        sync_scope_counts!(prefix, HeaderParser.app_counts(headers), "#{prefix}:app")
        sync_scope_counts!(prefix, HeaderParser.method_counts(headers), "#{prefix}:m:#{bucket}")
      end

      def sync_scope_counts!(_prefix, counts, counter_prefix)
        counts.each do |count, window|
          @redis.set("#{counter_prefix}:#{window}", count.to_s, ex: window)
        end
      end

      def serialize(pairs)
        pairs.map { |limit, window| "#{limit}:#{window}" }.join(',')
      end

      def parse_limits(value)
        HeaderParser.parse_pairs(value)
      end

      def prefix_for(key, region)
        "rito:#{digest(key)}:#{Routing.normalize(region)}"
      end

      def digest(key)
        Digest::SHA256.hexdigest(key.to_s)[0, 16]
      end
    end
  end
end
