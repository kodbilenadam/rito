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
          local limit = tonumber(ARGV[(i - 3) * 2 + 1])
          if tonumber(redis.call('GET', KEYS[i]) or '0') >= limit then
            return 0
          end
        end
        for i = 3, #KEYS do
          redis.call('INCR', KEYS[i])
          if redis.call('PTTL', KEYS[i]) < 0 then
            redis.call('EXPIRE', KEYS[i], ARGV[(i - 3) * 2 + 2])
          end
        end
        return 1
      LUA

      BLOCK_SCRIPT = <<~LUA
        local streak = math.min(redis.call('INCR', KEYS[2]), 6)
        redis.call('EXPIRE', KEYS[2], 600)
        local delay = tonumber(ARGV[1])
        if delay < 0 then
          delay = math.min(2 ^ (streak - 1), 32) * 1000 + tonumber(ARGV[2])
        end
        if delay > 0 and redis.call('PTTL', KEYS[1]) < delay then
          redis.call('SET', KEYS[1], '1', 'PX', delay)
        end
      LUA

      SYNC_COUNT_SCRIPT = <<~LUA
        local current = redis.call('GET', KEYS[1])
        local count = tonumber(ARGV[1])
        if not current then
          redis.call('SET', KEYS[1], count, 'EX', ARGV[2])
        elseif count > tonumber(current) then
          local ttl = redis.call('PTTL', KEYS[1])
          if ttl > 0 then
            redis.call('SET', KEYS[1], count, 'PX', ttl)
          else
            redis.call('SET', KEYS[1], count, 'EX', ARGV[2])
          end
        end
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

        sync_limits!(prefix, bucket, headers)
        sync_counts!(prefix, bucket, headers)
        if status == 429
          block!(prefix, bucket, headers)
        else
          @redis.del("#{prefix}:block:streak", "#{prefix}:m:#{bucket}:block:streak")
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
        retry_after = HeaderParser.retry_after(headers)
        block_key = if HeaderParser.limit_type(headers) == :application
                      "#{prefix}:block"
                    else
                      "#{prefix}:m:#{bucket}:block"
                    end
        @redis.eval(BLOCK_SCRIPT, keys: [block_key, "#{block_key}:streak"],
                                  argv: [retry_after ? retry_after * 1000 : -1, rand(500)])
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
        sync_scope_counts!(HeaderParser.app_counts(headers), "#{prefix}:app")
        sync_scope_counts!(HeaderParser.method_counts(headers), "#{prefix}:m:#{bucket}")
      end

      def sync_scope_counts!(counts, counter_prefix)
        counts.each do |count, window|
          @redis.eval(SYNC_COUNT_SCRIPT, keys: ["#{counter_prefix}:#{window}"], argv: [count, window])
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
