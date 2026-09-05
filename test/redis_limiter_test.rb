# frozen_string_literal: true

require_relative 'test_helper'
require 'redis'
require 'securerandom'

class RedisLimiterTest < Minitest::Test
  def setup
    @redis_available = begin
      redis = Redis.new(url: ENV['REDIS_URL'] || 'redis://127.0.0.1:6379')
      redis.ping == 'PONG'
    rescue StandardError
      raise if ENV['REDIS_URL']

      false
    end
    skip 'no Redis available' unless @redis_available

    @redis = Redis.new(url: ENV['REDIS_URL'] || 'redis://127.0.0.1:6379')
    @unique = SecureRandom.hex(4)
    @slept = []
    # sleeper simulates window expiry by draining counters
    @limiter = Rito::RateLimiting::RedisLimiter.new(
      redis: @redis,
      sleeper: lambda { |delay|
        @slept << delay
        prefix = Digest::SHA256.hexdigest(@unique)[0, 16]
        @redis.keys("rito:#{prefix}:na1:app:*").each { |k| @redis.decr(k) }
      }
    )
  end

  def teardown
    return unless @unique

    keys = @redis.keys("rito:#{digest(@unique)}:*")
    @redis.del(*keys) unless keys.empty?
  end

  def response(status, headers)
    env = Faraday::Env.new(:get, nil, URI('https://na1.api.riotgames.com/lol/summoner/v4/x'),
                           nil, {}, nil, nil, nil, nil, headers, status, 'OK', '{}')
    Faraday::Response.new(env)
  end

  def test_permissive_before_limits_are_known
    @limiter.acquire!(key: @unique, region: 'na1', bucket: 'lol/summoner')
    assert_empty @slept
  end

  def test_learns_limits_and_blocks_at_ceiling
    @limiter.observe!(response(200, { 'X-App-Rate-Limit' => '2:10',
                                      'X-App-Rate-Limit-Count' => '1:10' }),
                      key: @unique, region: 'na1', bucket: 'lol/summoner')

    @limiter.acquire!(key: @unique, region: 'na1', bucket: 'lol/summoner')
    @limiter.acquire!(key: @unique, region: 'na1', bucket: 'lol/summoner')

    assert_equal [1], @slept
  end

  def test_429_with_retry_after_sets_block_key
    @limiter.observe!(response(429, { 'Retry-After' => '5',
                                      'X-Rate-Limit-Type' => 'application',
                                      'X-App-Rate-Limit' => '10:10',
                                      'X-App-Rate-Limit-Count' => '11:10' }),
                      key: @unique, region: 'na1', bucket: 'lol/summoner')

    assert @limiter.blocked?(key: @unique, region: 'na1', scope: :app)
    ttl = @redis.ttl(@redis.keys('rito:*:na1:block').find { |k| k.include?(digest(@unique)) })
    assert_operator ttl, :>, 0
    assert_operator ttl, :<=, 5
  end

  def test_method_429_does_not_block_app_scope
    @limiter.observe!(response(429, { 'Retry-After' => '3',
                                      'X-Rate-Limit-Type' => 'method',
                                      'X-App-Rate-Limit' => '10:10',
                                      'X-App-Rate-Limit-Count' => '1:10' }),
                      key: @unique, region: 'na1', bucket: 'lol/summoner')

    assert @limiter.blocked?(key: @unique, region: 'na1', bucket: 'lol/summoner', scope: :method)
    refute @limiter.blocked?(key: @unique, region: 'na1', scope: :app)
  end

  def test_keys_are_isolated_in_redis
    @limiter.observe!(response(429, { 'Retry-After' => '3',
                                      'X-Rate-Limit-Type' => 'application' }),
                      key: @unique, region: 'na1', bucket: 'lol/summoner')

    assert @limiter.blocked?(key: @unique, region: 'na1', scope: :app)
    refute @limiter.blocked?(key: "#{@unique}-other", region: 'na1', scope: :app)
  end

  def test_missing_redis_gem_raises_helpful_error
    redis_class = ::Redis
    Object.send(:remove_const, :Redis)
    begin
      error = assert_raises(Rito::RateLimiting::RedisLimiter::DependencyMissing) do
        Rito::RateLimiting::RedisLimiter.new(redis: nil)
      end
      assert_match(/`redis` gem/, error.message)
    ensure
      Object.const_set(:Redis, redis_class)
    end
  end

  def test_rejected_acquires_do_not_consume_other_windows
    headers = { 'X-App-Rate-Limit' => '10:120,100:600', 'X-App-Rate-Limit-Count' => '0:120,0:600',
                'X-Method-Rate-Limit' => '1:120', 'X-Method-Rate-Limit-Count' => '1:120' }
    @limiter.observe!(response(200, headers), key: @unique, region: 'na1', bucket: 'lol/summoner')
    limiter = Rito::RateLimiting::RedisLimiter.new(redis: @redis, sleeper: ->(_) { raise ThreadError, 'blocked' })
    3.times do
      assert_raises(ThreadError) { limiter.acquire!(key: @unique, region: 'na1', bucket: 'lol/summoner') }
    end
    assert_equal '0', @redis.get("rito:#{digest(@unique)}:na1:app:120")
    assert_equal '0', @redis.get("rito:#{digest(@unique)}:na1:app:600")
  end

  def test_zero_retry_after_does_not_raise_or_block
    @limiter.observe!(response(429, { 'Retry-After' => '0', 'X-Rate-Limit-Type' => 'application' }),
                      key: @unique, region: 'na1', bucket: 'lol/summoner')
    @limiter.acquire!(key: @unique, region: 'na1', bucket: 'lol/summoner')
    assert_empty @slept
  end

  def test_shorter_retry_after_does_not_shorten_an_existing_block
    [30, 1].each do |seconds|
      @limiter.observe!(response(429, { 'Retry-After' => seconds.to_s, 'X-Rate-Limit-Type' => 'application' }),
                        key: @unique, region: 'na1', bucket: 'lol/summoner')
    end
    assert_operator @redis.ttl("rito:#{digest(@unique)}:na1:block"), :>=, 29
  end

  def test_missing_retry_after_backoff_grows_and_resets_after_success
    block = "rito:#{digest(@unique)}:na1:m:lol/summoner:block"
    [1, 2, 4].each do |minimum|
      @limiter.observe!(response(429, {}), key: @unique, region: 'na1', bucket: 'lol/summoner')
      assert_operator @redis.pttl(block), :>=, minimum * 1000 - 100
    end
    @redis.del(block)
    @limiter.observe!(response(200, {}), key: @unique, region: 'na1', bucket: 'lol/summoner')
    @limiter.observe!(response(429, {}), key: @unique, region: 'na1', bucket: 'lol/summoner')
    assert_operator @redis.pttl(block), :<=, 1500
  end

  def test_sync_preserves_window_deadlines_and_in_flight_counts
    counter = "rito:#{digest(@unique)}:na1:app:120"
    @redis.set(counter, '4', px: 3000)
    [2, 5].each do |count|
      @limiter.observe!(response(200, { 'X-App-Rate-Limit-Count' => "#{count}:120" }),
                        key: @unique, region: 'na1', bucket: 'lol/summoner')
      assert_equal [4, count].max.to_s, @redis.get(counter)
      assert_operator @redis.pttl(counter), :<=, 3000
    end
  end

  def test_concurrent_workers_share_atomic_quota
    @limiter.observe!(response(200, { 'X-App-Rate-Limit' => '5:120', 'X-App-Rate-Limit-Count' => '0:120' }),
                      key: @unique, region: 'na1', bucket: 'lol/summoner')
    results = 12.times.map do
      Thread.new do
        limiter = Rito::RateLimiting::RedisLimiter.new(redis: @redis, sleeper: ->(_) { raise ThreadError, 'blocked' })
        limiter.acquire!(key: @unique, region: 'na1', bucket: 'lol/summoner')
        true
      rescue ThreadError
        false
      end
    end.map(&:value)
    assert_equal 5, results.count(true)
    assert_equal '5', @redis.get("rito:#{digest(@unique)}:na1:app:120")
  end

  def digest(key)
    Digest::SHA256.hexdigest(key)[0, 16]
  end
end
