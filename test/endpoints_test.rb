# frozen_string_literal: true

require_relative 'test_helper'

class SummonerEndpointTest < Minitest::Test
  def setup
    WebMock.reset!
    @client = Rito::Client.new(api_key: 'RGAPI-test', region: :na1, rate_limiter: Rito::RateLimiting::NullLimiter.new)
  end

  def teardown
    WebMock.reset!
  end

  def test_by_name_returns_summoner_model
    body = '{"id":"sum-id","accountId":"acc-id","puuid":"puuid-1","name":"Hide on bush",' \
           '"profileIconId":11,"revisionDate":1700000000000,"summonerLevel":1024}'
    stub_request(:get, 'https://na1.api.riotgames.com/lol/summoner/v4/summoners/by-name/Hide%20on%20bush')
      .with(headers: { 'X-Riot-Token' => 'RGAPI-test' })
      .to_return(status: 200, headers: { 'Content-Type' => 'application/json' }, body: body)

    summoner = @client.summoner.by_name('Hide on bush')

    assert_equal 'sum-id', summoner.id
    assert_equal 'acc-id', summoner.account_id
    assert_equal 'puuid-1', summoner.puuid
    assert_equal 'Hide on bush', summoner.name
    assert_equal 1024, summoner.summoner_level
  end

  def test_by_puuid_escapes_and_routes_to_platform
    stub = stub_request(:get, 'https://euw1.api.riotgames.com/lol/summoner/v4/summoners/by-puuid/p%2Fuuid')
           .to_return(status: 200, headers: { 'Content-Type' => 'application/json' }, body: '{}')

    summoner = @client.summoner.by_puuid('p/uuid', region: :euw1)

    assert_requested stub
    assert_nil summoner.id
    assert_equal({}, summoner.raw)
  end

  def test_preserves_unknown_fields_in_raw
    stub_request(:get, 'https://na1.api.riotgames.com/lol/summoner/v4/summoners/by-name/x')
      .to_return(status: 200, headers: { 'Content-Type' => 'application/json' },
                 body: '{"name":"x","brandNewField":"future-proof"}')

    summoner = @client.summoner.by_name('x')

    assert_equal 'future-proof', summoner.raw['brandNewField']
  end
end

class AccountEndpointTest < Minitest::Test
  def setup
    WebMock.reset!
    @client = Rito::Client.new(api_key: 'RGAPI-test', region: :na1, rate_limiter: Rito::RateLimiting::NullLimiter.new)
  end

  def teardown
    WebMock.reset!
  end

  def test_by_riot_id_escalates_platform_to_regional_cluster
    stub = stub_request(:get, 'https://americas.api.riotgames.com/riot/account/v1/accounts/by-riot-id/Faker/KR1')
           .to_return(status: 200, headers: { 'Content-Type' => 'application/json' },
                      body: '{"puuid":"p1","gameName":"Faker","tagLine":"KR1"}')

    account = @client.account.by_riot_id('Faker', 'KR1')

    assert_requested stub
    assert_equal 'p1', account.puuid
    assert_equal 'Faker', account.game_name
    assert_equal 'KR1', account.tag_line
  end

  def test_sea_is_normalized_to_asia_for_account_api
    stub = stub_request(:get, 'https://asia.api.riotgames.com/riot/account/v1/accounts/by-puuid/p1')
           .to_return(status: 200, headers: { 'Content-Type' => 'application/json' }, body: '{"puuid":"p1"}')

    @client.account.by_puuid('p1', region: :sea)

    assert_requested stub
  end

  def test_active_shard
    stub_request(:get, 'https://asia.api.riotgames.com/riot/account/v1/active-shards/by-game/val/by-puuid/p1')
      .to_return(status: 200, headers: { 'Content-Type' => 'application/json' },
                 body: '{"puuid":"p1","game":"val","activeShard":"ap"}')

    shard = @client.account.active_shard('val', 'p1', region: :asia)

    assert_equal 'ap', shard.active_shard
  end
end

class ErrorHandlingTest < Minitest::Test
  def setup
    WebMock.reset!
  end

  def teardown
    WebMock.reset!
  end

  def client
    Rito::Client.new(api_key: 'RGAPI-test', region: :na1, rate_limiter: Rito::RateLimiting::NullLimiter.new)
  end

  def test_404_raises_not_found_with_url
    stub_request(:get, 'https://na1.api.riotgames.com/lol/summoner/v4/summoners/by-name/ghost')
      .to_return(status: 404, headers: { 'Content-Type' => 'application/json' },
                 body: '{"message":"Data not found: summoner not found"}')

    error = assert_raises(Rito::NotFound) { client.summoner.by_name('ghost') }

    assert_equal 404, error.status
    assert_includes error.message, 'summoner not found'
  end

  def test_401_raises_unauthorized
    stub_request(:get, 'https://na1.api.riotgames.com/lol/summoner/v4/summoners/by-name/x').to_return(status: 401)

    assert_raises(Rito::Unauthorized) { client.summoner.by_name('x') }
  end

  def test_403_raises_forbidden
    stub_request(:get, 'https://na1.api.riotgames.com/lol/summoner/v4/summoners/by-name/x').to_return(status: 403)

    error = assert_raises(Rito::Forbidden) { client.summoner.by_name('x') }

    assert_includes error.message, 'dev keys expire every 24h'
  end

  def test_503_raises_service_unavailable_after_retries
    stub = stub_request(:get, 'https://na1.api.riotgames.com/lol/summoner/v4/summoners/by-name/x')
           .to_return(status: 503)

    assert_raises(Rito::ServiceUnavailable) { client.summoner.by_name('x') }

    assert_requested(stub, times: 4)
  end

  def test_429_is_retried_until_success
    stub_request(:get, 'https://na1.api.riotgames.com/lol/summoner/v4/summoners/by-name/ok')
      .to_return(status: 429,
                 headers: { 'Retry-After' => '0', 'X-Rate-Limit-Type' => 'application',
                            'X-App-Rate-Limit' => '20:1', 'X-App-Rate-Limit-Count' => '21:1' },
                 body: '{}')
      .times(2)
      .then.to_return(status: 200, headers: { 'Content-Type' => 'application/json' },
                      body: '{"name":"ok"}')

    summoner = client.summoner.by_name('ok')

    assert_equal 'ok', summoner.name
  end

  def test_429_retries_exhausted_raises_rate_limited
    stub_request(:get, 'https://na1.api.riotgames.com/lol/summoner/v4/summoners/by-name/x')
      .to_return(status: 429, headers: { 'Retry-After' => '0', 'X-Rate-Limit-Type' => 'method' }, body: '{}')

    error = assert_raises(Rito::RateLimited) { client.summoner.by_name('x') }

    assert_equal 429, error.status
    assert_equal 0, error.retry_after
    assert_equal :method, error.limit_type
  end
end
