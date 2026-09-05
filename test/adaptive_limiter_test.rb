# frozen_string_literal: true

require_relative 'test_helper'

class AdaptiveLimiterTest < Minitest::Test
  def setup
    @now = 0.0
    @waited = 0.0
    sleeper = lambda { |delay|
      @waited += delay
      @now += delay
    }
    @limiter = Rito::RateLimiting::AdaptiveLimiter.new(clock: -> { @now }, sleeper: sleeper)
    @response = lambda do |status, headers|
      Faraday::Response.new(Faraday::Env.new(:get, nil, URI('https://na1.api.riotgames.com/x'), nil, {}, nil, nil, nil,
                                             nil, headers, status, 'OK', '{}'))
    end
  end

  def observe(status, headers)
    @limiter.observe!(@response.call(status, headers), key: 'key', region: 'na1', bucket: 'lol/summoner')
  end

  def test_allows_requests_before_headers_are_known
    @limiter.acquire!(key: 'key', region: 'na1', bucket: 'lol/summoner')
    pass
  end

  def test_blocks_when_app_limit_reached
    observe(200, { 'X-App-Rate-Limit' => '2:10', 'X-App-Rate-Limit-Count' => '1:10' })

    @limiter.acquire!(key: 'key', region: 'na1', bucket: 'lol/summoner')
    assert_equal 0.0, @waited

    @limiter.acquire!(key: 'key', region: 'na1', bucket: 'lol/summoner')

    assert @waited.positive?
  end

  def test_method_limit_is_per_endpoint
    observe(200, { 'X-App-Rate-Limit' => '100:10', 'X-App-Rate-Limit-Count' => '0:10',
                   'X-Method-Rate-Limit' => '1:10', 'X-Method-Rate-Limit-Count' => '0:10' })

    @limiter.acquire!(key: 'key', region: 'na1', bucket: 'lol/summoner')
    assert_equal 0.0, @waited

    @limiter.acquire!(key: 'key', region: 'na1', bucket: 'lol/summoner')
    assert @waited.positive?

    waited_before = @waited
    @limiter.acquire!(key: 'key', region: 'na1', bucket: 'lol/match')
    assert_equal waited_before, @waited
  end

  def test_keys_and_regions_are_isolated
    observe(200, { 'X-App-Rate-Limit' => '1:10', 'X-App-Rate-Limit-Count' => '1:10' })

    @limiter.acquire!(key: 'key', region: 'na1', bucket: 'lol/summoner')
    assert @waited.positive?

    waited_before = @waited
    @limiter.acquire!(key: 'other', region: 'na1', bucket: 'lol/summoner')
    @limiter.acquire!(key: 'key', region: 'kr', bucket: 'lol/summoner')
    assert_equal waited_before, @waited
  end

  def test_429_with_retry_after_blocks_app_scope
    observe(200, { 'X-App-Rate-Limit' => '10:10', 'X-App-Rate-Limit-Count' => '0:10' })
    observe(429, { 'X-App-Rate-Limit' => '10:10', 'X-App-Rate-Limit-Count' => '11:10',
                   'Retry-After' => '5', 'X-Rate-Limit-Type' => 'application' })

    @now = 1.0
    assert @limiter.bucket_blocked?(key: 'key', region: 'na1', scope: :app)

    @now = 6.5
    refute @limiter.bucket_blocked?(key: 'key', region: 'na1', scope: :app)
  end

  def test_429_with_method_type_only_blocks_method_bucket
    observe(429, { 'X-App-Rate-Limit' => '10:10', 'X-App-Rate-Limit-Count' => '1:10',
                   'X-Method-Rate-Limit' => '10:10', 'X-Method-Rate-Limit-Count' => '11:10',
                   'Retry-After' => '3', 'X-Rate-Limit-Type' => 'method' })

    @now = 1.0
    assert @limiter.bucket_blocked?(key: 'key', region: 'na1', bucket: 'lol/summoner', scope: :method)
    refute @limiter.bucket_blocked?(key: 'key', region: 'na1', scope: :app)
  end

  def test_429_without_type_or_retry_after_blocks_method_bucket
    observe(429, { 'X-App-Rate-Limit' => '10:10', 'X-App-Rate-Limit-Count' => '1:10' })

    @now = 1.0
    assert @limiter.bucket_blocked?(key: 'key', region: 'na1', bucket: 'lol/summoner', scope: :method)
    refute @limiter.bucket_blocked?(key: 'key', region: 'na1', scope: :app)
  end

  def test_header_counts_authoritative_over_local
    observe(200, { 'X-App-Rate-Limit' => '10:10', 'X-App-Rate-Limit-Count' => '0:10' })

    3.times { @limiter.acquire!(key: 'key', region: 'na1', bucket: 'lol/summoner') }

    observe(200, { 'X-App-Rate-Limit' => '10:10', 'X-App-Rate-Limit-Count' => '1:10' })

    @now = 9.0
    refute @limiter.bucket_blocked?(key: 'key', region: 'na1', scope: :app)
    @limiter.acquire!(key: 'key', region: 'na1', bucket: 'lol/summoner')
  end

  def test_backoff_grows_without_retry_after_and_resets_after_success
    [1, 2, 4, 8, 16, 32, 32].each do |minimum|
      before = @waited
      observe(429, {})
      @limiter.acquire!(key: 'key', region: 'na1', bucket: 'lol/summoner')
      assert_operator @waited - before, :>=, minimum
      assert_operator @waited - before, :<, minimum + 0.502
    end
    observe(200, {})
    before = @waited
    observe(429, {})
    @limiter.acquire!(key: 'key', region: 'na1', bucket: 'lol/summoner')
    assert_operator @waited - before, :<, 1.502
  end

  def test_window_deadlines_do_not_slide_with_each_response
    observe(200, { 'X-App-Rate-Limit' => '2:10', 'X-App-Rate-Limit-Count' => '1:10' })
    @now = 8.0
    observe(200, { 'X-App-Rate-Limit' => '2:10', 'X-App-Rate-Limit-Count' => '2:10' })
    @limiter.acquire!(key: 'key', region: 'na1', bucket: 'lol/summoner')
    assert_in_delta 2.001, @waited, 0.001
  end

  def test_limits_remain_known_after_a_window_expires
    observe(200, { 'X-App-Rate-Limit' => '1:10', 'X-App-Rate-Limit-Count' => '1:10' })
    3.times { @limiter.acquire!(key: 'key', region: 'na1', bucket: 'lol/summoner') }
    assert_in_delta 30.003, @waited, 0.001
  end

  def test_out_of_order_counts_do_not_restore_quota
    observe(200, { 'X-App-Rate-Limit' => '2:10', 'X-App-Rate-Limit-Count' => '2:10' })
    observe(200, { 'X-App-Rate-Limit' => '2:10', 'X-App-Rate-Limit-Count' => '1:10' })
    @limiter.acquire!(key: 'key', region: 'na1', bucket: 'lol/summoner')
    assert_operator @waited, :>=, 10
  end

  def test_waiting_for_method_quota_does_not_reserve_application_quota
    other_call = false
    limiter = nil
    sleeper = lambda { |delay|
      unless other_call
        other_call = true
        limiter.acquire!(key: 'key', region: 'na1', bucket: 'lol/status')
      end
      @now += delay
    }
    limiter = Rito::RateLimiting::AdaptiveLimiter.new(clock: -> { @now }, sleeper: sleeper)
    limiter.observe!(@response.call(200, { 'X-App-Rate-Limit' => '1:100', 'X-App-Rate-Limit-Count' => '0:100',
                                           'X-Method-Rate-Limit' => '1:10', 'X-Method-Rate-Limit-Count' => '1:10' }),
                     key: 'key', region: 'na1', bucket: 'lol/summoner')
    limiter.acquire!(key: 'key', region: 'na1', bucket: 'lol/summoner')
    assert other_call
    assert_in_delta 100.001, @now, 0.001
  end

  def test_concurrent_acquires_are_thread_safe
    observe(200, { 'X-App-Rate-Limit' => '100:10', 'X-App-Rate-Limit-Count' => '0:10' })

    threads = 10.times.map do
      Thread.new do
        5.times { @limiter.acquire!(key: 'key', region: 'na1', bucket: 'lol/summoner') }
      end
    end
    threads.each(&:join)

    assert_equal 0.0, @waited
    app_bucket = @limiter.instance_variable_get(:@buckets)[['app', 'key', 'na1', nil]]
    assert_equal 50, app_bucket.instance_variable_get(:@windows).first[:count]
  end
end
