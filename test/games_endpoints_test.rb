# frozen_string_literal: true

require_relative 'test_helper'

class TftEndpointTest < Minitest::Test
  def setup
    WebMock.reset!
    @client = Rito::Client.new(api_key: 'RGAPI-test', region: :na1,
                               rate_limiter: Rito::RateLimiting::NullLimiter.new)
  end

  def teardown
    WebMock.reset!
  end

  def test_summoner_by_puuid_routes_to_platform
    stub = stub_request(:get, 'https://na1.api.riotgames.com/tft/summoner/v1/summoners/by-puuid/p1')
           .to_return(status: 200, headers: { 'Content-Type' => 'application/json' },
                      body: '{"puuid":"p1","id":"s1","accountId":"a1","name":"tft","summonerLevel":200}')

    summoner = @client.tft.summoner.by_puuid('p1')

    assert_requested stub
    assert_equal 'tft', summoner.name
  end

  def test_matches_escalate_to_regional_cluster
    stub = stub_request(:get, 'https://americas.api.riotgames.com/tft/match/v1/matches/by-puuid/p1/ids?count=5')
           .to_return(status: 200, headers: { 'Content-Type' => 'application/json' }, body: '["M1"]')

    ids = @client.tft.matches.ids_by_puuid('p1', count: 5, region: :na1)

    assert_requested stub
    assert_equal ['M1'], ids
  end

  def test_league_challenger_routes_to_platform
    stub = stub_request(:get, 'https://na1.api.riotgames.com/tft/league/v1/challenger')
           .to_return(status: 200, headers: { 'Content-Type' => 'application/json' },
                      body: '{"leagueId":"t1","tier":"CHALLENGER","entries":[]}')

    ladder = @client.tft.leagues.challenger(region: :na1)

    assert_requested stub
    assert_equal 'CHALLENGER', ladder['tier']
  end

  def test_status_routes_to_platform
    stub = stub_request(:get, 'https://na1.api.riotgames.com/tft/status/v1/platform-data')
           .to_return(status: 200, headers: { 'Content-Type' => 'application/json' },
                      body: '{"id":"NA1","incidents":[]}')

    @client.tft.status.platform_data

    assert_requested stub
  end

  def test_spectator_active_game_nil_on_404
    stub_request(:get, 'https://na1.api.riotgames.com/lol/spectator/tft/v5/active-games/by-puuid/p1')
      .to_return(status: 404, body: '{}')

    assert_nil @client.tft.spectator.active_game('p1')
  end
end

class ValorantEndpointTest < Minitest::Test
  def setup
    WebMock.reset!
    @client = Rito::Client.new(api_key: 'RGAPI-test', region: :na1,
                               rate_limiter: Rito::RateLimiting::NullLimiter.new)
  end

  def teardown
    WebMock.reset!
  end

  def test_uses_valorant_platform_routing
    stub = stub_request(:get, 'https://eu.api.riotgames.com/val/content/v1/contents')
           .to_return(status: 200, headers: { 'Content-Type' => 'application/json' }, body: '{"categories":[]}')

    @client.val.content.contents(region: :eu)

    assert_requested stub
  end

  def test_rejects_lol_platform_for_valorant
    assert_raises(ArgumentError) do
      @client.val.matches.by_id('M1', region: :euw1)
    end
  end

  def test_accepts_valorant_platforms
    stub = stub_request(:get, 'https://latam.api.riotgames.com/val/status/v1/platform-data')
           .to_return(status: 200, headers: { 'Content-Type' => 'application/json' }, body: '{"id":null}')

    @client.val.status.platform_data(region: :latam)

    assert_requested stub
  end

  def test_console_routing
    stub = stub_request(:get, 'https://na.api.riotgames.com/val/console/match/v1/matchlists/by-puuid/p1')
           .to_return(status: 200, headers: { 'Content-Type' => 'application/json' }, body: '{"puuid":"p1"}')

    @client.val.console_matches.ids_by_puuid('p1', region: :na)

    assert_requested stub
  end
end

class LorEndpointTest < Minitest::Test
  def setup
    WebMock.reset!
    @client = Rito::Client.new(api_key: 'RGAPI-test', region: :americas,
                               rate_limiter: Rito::RateLimiting::NullLimiter.new)
  end

  def teardown
    WebMock.reset!
  end

  def test_leaderboards_is_regional
    stub = stub_request(:get, 'https://americas.api.riotgames.com/lor/ranked/v1/leaderboards')
           .to_return(status: 200, headers: { 'Content-Type' => 'application/json' },
                      body: '{"players":[{"name":"kitten","rank":1}]}')

    board = @client.lor.ranked.leaderboards

    assert_requested stub
    assert_equal 'kitten', board['players'].first['name']
  end

  def test_matches_by_puuid
    stub = stub_request(:get, 'https://europe.api.riotgames.com/lor/match/v1/matches/by-puuid/p1/ids')
           .to_return(status: 200, headers: { 'Content-Type' => 'application/json' }, body: '["LOR1"]')

    ids = @client.lor.matches.ids_by_puuid('p1', region: :europe)

    assert_requested stub
    assert_equal ['LOR1'], ids
  end

  def test_deck_endpoints_exist_for_rso_clients
    rso_client = Rito::Client.new(bearer_token: 'at-123', region: :americas,
                                  rate_limiter: Rito::RateLimiting::NullLimiter.new)
    stub = stub_request(:get, 'https://americas.api.riotgames.com/lor/deck/v1/decks/me')
           .with(headers: { 'Authorization' => 'Bearer at-123' })
           .to_return(status: 200, headers: { 'Content-Type' => 'application/json' }, body: '{"decks":[]}')

    rso_client.lor.decks.my_decks

    assert_requested stub
  end
end

class RiftboundEndpointTest < Minitest::Test
  def setup
    WebMock.reset!
  end

  def teardown
    WebMock.reset!
  end

  def test_contents_is_regional
    client = Rito::Client.new(api_key: 'RGAPI-test', region: :americas,
                              rate_limiter: Rito::RateLimiting::NullLimiter.new)
    stub = stub_request(:get, 'https://americas.api.riotgames.com/riftbound/content/v1/contents')
           .to_return(status: 200, headers: { 'Content-Type' => 'application/json' }, body: '[]')

    client.riftbound.contents

    assert_requested stub
  end
end
