# frozen_string_literal: true

require_relative 'test_helper'

class RegressionsTest < Minitest::Test
  JSON_HEADERS = { 'Content-Type' => 'application/json' }.freeze
  STATUS_URL = 'https://na1.api.riotgames.com/lol/status/v4/platform-data'

  def client(**options)
    Rito::Client.new(api_key: 'test-key', max_retries: 1, rate_limiter: Rito::RateLimiting::NullLimiter.new, **options)
  end

  def test_league_entries_include_queue_and_escape_segments
    stub = stub_request(:get, 'https://na1.api.riotgames.com/lol/league/v4/entries/RANKED%2FSOLO/DIAMOND/I?page=2')
           .to_return(status: 200, headers: JSON_HEADERS, body: '[{"puuid":"p","tier":"DIAMOND","extra":true}]')

    entry = client.leagues.entries('RANKED/SOLO', 'DIAMOND', 'I', page: 2).first

    assert_requested stub
    assert_equal 'DIAMOND', entry.tier
    assert entry.raw['extra']
  end

  def test_tournaments_accept_americas_and_escalate_na1
    %i[tournaments tournament_stub].each do |accessor|
      path = accessor == :tournaments ? 'tournament' : 'tournament-stub'
      stub = stub_request(:get, "https://americas.api.riotgames.com/lol/#{path}/v5/codes/CODE")
             .to_return(status: 200, headers: JSON_HEADERS, body: '{}')
      endpoint = client.public_send(accessor)
      endpoint.code('CODE', region: :na1)
      endpoint.code('CODE', region: :americas)
      assert_requested stub, times: 2
      assert_raises(ArgumentError) { endpoint.code('CODE', region: :kr) }
      assert_raises(ArgumentError) { endpoint.code('CODE', region: :europe) }
    end
  end

  def test_sea_platforms_route_accounts_to_asia
    stub = stub_request(:get, 'https://asia.api.riotgames.com/riot/account/v1/accounts/by-puuid/p')
           .to_return(status: 200, headers: JSON_HEADERS, body: '{"puuid":"p"}')
    %i[sg2 tw2 vn2 oc1 sea].each { |region| client(region: region).account.by_puuid('p') }
    assert_requested stub, times: 5
    assert_raises(ArgumentError) { client.account.by_puuid('p', region: :esports) }
  end

  def test_valorant_client_defaults_are_usable
    %i[na eu ap kr br latam].each do |region|
      stub = stub_request(:get, "https://#{region}.api.riotgames.com/val/status/v1/platform-data")
             .to_return(status: 200, headers: JSON_HEADERS, body: '{}')
      client(region: region).val.status.platform_data
      assert_requested stub
    end
  end

  def test_bearer_client_overrides_global_api_key
    with_config(api_key: 'global-key') do
      stub = stub_request(:get, 'https://americas.api.riotgames.com/riot/account/v1/accounts/me')
             .with do |request|
               request.headers['Authorization'] == 'Bearer token' && !request.headers.key?('X-Riot-Token')
             end
             .to_return(status: 200, headers: JSON_HEADERS, body: '{}')
      Rito::Client.new(bearer_token: 'token').account.me
      Rito::Client.new(api_key: nil, bearer_token: 'token').account.me
      assert_requested stub, times: 2
    end
  end

  def test_explicit_nil_clears_credentials_and_mixed_credentials_are_rejected
    with_config(api_key: 'global-key') do
      assert_raises(Rito::ConfigError) { Rito::Client.new(api_key: nil) }
    end
    assert_raises(Rito::ConfigError) { Rito::Client.new(api_key: 'key', bearer_token: 'token') }
    with_config(bearer_token: 'global-token') do
      assert_nil Rito::Client.new(api_key: 'key').bearer_token
    end
  end

  def test_transport_failures_retry_before_conversion
    [Faraday::TimeoutError, Faraday::ConnectionFailed].each do |error_class|
      stub = stub_request(:get, STATUS_URL).to_raise(error_class).then
                                           .to_return(status: 200, headers: JSON_HEADERS, body: '{}')
      assert_equal({}, client.lol_status.platform_data)
      assert_requested stub, times: 2
      WebMock.reset!
    end
  end

  def test_exhausted_timeout_is_wrapped_after_retries
    stub = stub_request(:get, STATUS_URL).to_raise(Faraday::TimeoutError)
    error = assert_raises(Rito::TimeoutError) { client.lol_status.platform_data }
    assert_requested stub, times: 2
    assert_kind_of Faraday::TimeoutError, error.wrapped
  end

  def test_non_json_errors_keep_the_http_error_class
    stub_request(:get, STATUS_URL).to_return(status: 403, body: '<html>Forbidden</html>')
    error = assert_raises(Rito::Forbidden) { client.lol_status.platform_data }
    assert_equal 403, error.status
    assert_includes error.message, 'product access'
  end

  def test_429_post_retry_preserves_the_original_body
    stub = stub_request(:post, 'https://americas.api.riotgames.com/lol/tournament-stub/v5/codes?tournamentId=1')
           .with(body: '{"mapType":"SUMMONERS_RIFT"}')
           .to_return(status: 429, headers: JSON_HEADERS.merge('Retry-After' => '0'),
                      body: '{"status":{"message":"limited"}}')
           .then.to_return(status: 200, headers: JSON_HEADERS, body: '["CODE"]')
    codes = client.tournament_stub.create_codes(tournament_id: 1, body: { mapType: 'SUMMONERS_RIFT' })
    assert_equal ['CODE'], codes
    assert_requested stub, times: 2
  end

  def test_method_limits_do_not_block_other_lol_endpoints
    now = 0.0
    sleeps = []
    limiter = Rito::RateLimiting::AdaptiveLimiter.new(clock: -> { now }, sleeper: lambda { |delay|
      sleeps << delay
      now += delay
    })
    c = client(rate_limiter: limiter, max_retries: 0)
    stub_request(:get, 'https://na1.api.riotgames.com/lol/summoner/v4/summoners/by-puuid/p')
      .to_return(status: 429, headers: JSON_HEADERS.merge('Retry-After' => '10',
                                                          'X-Rate-Limit-Type' => 'method'), body: '{}')
    assert_raises(Rito::RateLimited) { c.summoner.by_puuid('p') }
    stub_request(:get, STATUS_URL).to_return(status: 200, headers: JSON_HEADERS, body: '{}')
    c.lol_status.platform_data
    assert_empty sleeps
    assert limiter.bucket_blocked?(key: 'test-key', region: :na1, bucket: 'lol/summoner', scope: :method)
  end

  def test_instrumentation_reports_one_event_including_all_attempts
    stub_request(:get, STATUS_URL).to_return(status: 503).then
                                  .to_return(status: 429, headers: { 'Retry-After' => '0' }).then
                                  .to_return(status: 200, headers: JSON_HEADERS, body: '{}')
    events = []
    Rito::Instrumentation.stub(:emit, ->(payload) { events << payload }) { client.lol_status.platform_data }
    assert_equal 1, events.size
    assert_equal 3, events.first[:attempts]
    assert_equal 200, events.first[:status]
    assert_nil events.first[:error]
  end

  def test_instrumentation_reports_http_and_transport_failures
    stub_request(:get, STATUS_URL).to_return(status: 404)
    events = []
    Rito::Instrumentation.stub(:emit, ->(payload) { events << payload }) do
      assert_raises(Rito::NotFound) { client.lol_status.platform_data }
    end
    assert_equal 404, events.first[:status]
    assert_equal 'Rito::NotFound', events.first[:error]
    assert_equal 1, events.first[:attempts]
    stub_request(:get, STATUS_URL).to_raise(Faraday::TimeoutError)
    events.clear
    Rito::Instrumentation.stub(:emit, ->(payload) { events << payload }) do
      assert_raises(Rito::TimeoutError) { client.lol_status.platform_data }
    end
    assert_equal 1, events.size
    assert_equal 2, events.first[:attempts]
    assert_equal 'Rito::TimeoutError', events.first[:error]
  end

  def test_bearer_requests_are_instrumented
    stub_request(:get, 'https://americas.api.riotgames.com/riot/account/v1/accounts/me')
      .to_return(status: 200, headers: JSON_HEADERS, body: '{}')
    events = []
    Rito::Instrumentation.stub(:emit, ->(payload) { events << payload }) do
      Rito::Client.new(bearer_token: 'token').account.me
    end
    assert_equal 1, events.size
    assert_equal 200, events.first[:status]
    assert_equal 1, events.first[:attempts]
  end

  def test_nested_model_values_and_unknown_fields_are_frozen
    payload = JSON.parse('{"metadata":{"participants":["p"]},"info":{"gameMode":"CLASSIC",' \
                         '"participants":[{"puuid":"p"}],"future":{"values":["x"]}}}')
    match = Rito::Models::Match.from_api(payload)
    assert_raises(FrozenError) { match.info.game_mode.replace('MUTATED') }
    assert_raises(FrozenError) { match.metadata.participants << 'other' }
    assert_raises(FrozenError) { match.info.participants.clear }
    assert_raises(FrozenError) { match.info.raw['future']['values'].first.replace('changed') }
    assert_equal 'CLASSIC', match.info.raw['gameMode']
  end

  def test_rso_token_grants_are_never_retried
    rso = Rito::RSO::Client.new(client_id: 'client', client_secret: 'secret', redirect_uri: 'https://example.com/callback')
    stub = stub_request(:post, 'https://auth.riotgames.com/token').to_raise(Faraday::TimeoutError)
    assert_raises(Rito::TimeoutError) { rso.exchange_code('code') }
    assert_requested stub, times: 1
    assert_raises(Rito::TimeoutError) { rso.refresh('refresh') }
    assert_requested stub, times: 2
  end
end
