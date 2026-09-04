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

  def digest(key)
    Digest::SHA256.hexdigest(key)[0, 16]
  end
end
