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

  def test_summoner_me_uses_bearer_token
    stub = stub_request(:get, 'https://na1.api.riotgames.com/tft/summoner/v1/summoners/me')
           .with(headers: { 'Authorization' => 'Bearer at-123' })
           .to_return(status: 200, headers: { 'Content-Type' => 'application/json' },
                      body: '{"puuid":"p1","name":"tft-me","summonerLevel":120}')

    summoner = Rito::Client.new(bearer_token: 'at-123', region: :na1,
                                rate_limiter: Rito::RateLimiting::NullLimiter.new).tft.summoner.me

    assert_requested stub
    assert_equal 'tft-me', summoner.name
  end

  def test_league_ladders_route_to_platform
    grandmaster_stub = stub_request(:get, 'https://na1.api.riotgames.com/tft/league/v1/grandmaster')
                       .to_return(status: 200, headers: { 'Content-Type' => 'application/json' },
                                  body: '{"tier":"GRANDMASTER","entries":[]}')
    master_stub = stub_request(:get, 'https://na1.api.riotgames.com/tft/league/v1/master')
                  .to_return(status: 200, headers: { 'Content-Type' => 'application/json' },
                             body: '{"tier":"MASTER","entries":[]}')

    assert_equal 'GRANDMASTER', @client.tft.leagues.grandmaster['tier']
    assert_equal 'MASTER', @client.tft.leagues.master['tier']
    assert_requested grandmaster_stub
    assert_requested master_stub
  end

  def test_rated_ladder_top
    stub = stub_request(:get, 'https://na1.api.riotgames.com/tft/league/v1/rated-ladders/RANKED_TFT_TURBO/top')
           .to_return(status: 200, headers: { 'Content-Type' => 'application/json' },
                      body: '{"players":[{"puuid":"p1"}]}')

    ladder = @client.tft.leagues.rated_ladder_top('RANKED_TFT_TURBO')

    assert_requested stub
    assert_equal 'p1', ladder['players'].first['puuid']
  end

  def test_match_by_id_escalates_to_regional
    stub = stub_request(:get, 'https://americas.api.riotgames.com/tft/match/v1/matches/NA1_1')
           .to_return(status: 200, headers: { 'Content-Type' => 'application/json' },
                      body: '{"metadata":{"match_id":"NA1_1"},"info":{}}')

    match = @client.tft.matches.by_id('NA1_1')

    assert_requested stub
    assert_equal 'NA1_1', match['metadata']['match_id']
  end

  def test_match_ids_accept_esports_regional
    stub = stub_request(:get, 'https://esports.api.riotgames.com/tft/match/v1/matches/by-puuid/p1/ids')
           .to_return(status: 200, headers: { 'Content-Type' => 'application/json' }, body: '["ES_1"]')

    ids = @client.tft.matches.ids_by_puuid('p1', region: :esports)

    assert_requested stub
    assert_equal ['ES_1'], ids
  end

  def test_match_ids_send_time_window_params
    stub = stub_request(
      :get, 'https://americas.api.riotgames.com/tft/match/v1/matches/by-puuid/p1/ids?count=5&endTime=200&start=1&startTime=100'
    ).to_return(status: 200, headers: { 'Content-Type' => 'application/json' }, body: '[]')

    @client.tft.matches.ids_by_puuid('p1', count: 5, start: 1, start_time: 100, end_time: 200, region: :na1)

    assert_requested stub
  end

  def test_ladders_send_queue_filter
    stubs = %w[challenger grandmaster master].map do |ladder|
      stub_request(:get, "https://na1.api.riotgames.com/tft/league/v1/#{ladder}?queue=RANKED_TFT_DOUBLE_UP")
        .to_return(status: 200, headers: { 'Content-Type' => 'application/json' }, body: '{"entries":[]}')
    end

    @client.tft.leagues.challenger(queue: 'RANKED_TFT_DOUBLE_UP')
    @client.tft.leagues.grandmaster(queue: 'RANKED_TFT_DOUBLE_UP')
    @client.tft.leagues.master(queue: 'RANKED_TFT_DOUBLE_UP')

    stubs.each { |stub| assert_requested stub }
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
    stub = stub_request(
      :get, 'https://na.api.riotgames.com/val/match/console/v1/matchlists/by-puuid/p1?platformType=xbox'
    ).to_return(status: 200, headers: { 'Content-Type' => 'application/json' }, body: '{"puuid":"p1"}')

    @client.val.console_matches.ids_by_puuid('p1', platform_type: 'xbox', region: :na)

    assert_requested stub
  end

  def test_match_by_id_routes_to_valorant_platform
    stub = stub_request(:get, 'https://eu.api.riotgames.com/val/match/v1/matches/M1')
           .to_return(status: 200, headers: { 'Content-Type' => 'application/json' },
                      body: '{"matchInfo":{"matchId":"M1"}}')

    match = @client.val.matches.by_id('M1', region: :eu)

    assert_requested stub
    assert_equal 'M1', match['matchInfo']['matchId']
  end

  def test_recent_matches_by_queue
    stub = stub_request(:get, 'https://na.api.riotgames.com/val/match/v1/recent-matches/by-queue/competitive')
           .to_return(status: 200, headers: { 'Content-Type' => 'application/json' }, body: '{"currentTime":"1"}')

    recent = @client.val.matches.recent_by_queue('competitive', region: :na)

    assert_requested stub
    assert_equal '1', recent['currentTime']
  end

  def test_ranked_leaderboard_sends_paging_params
    stub = stub_request(
      :get, 'https://na.api.riotgames.com/val/ranked/v1/leaderboards/by-act/a1?size=200&startIndex=10'
    ).to_return(status: 200, headers: { 'Content-Type' => 'application/json' },
                body: '{"players":[{"puuid":"p1","leaderboardRank":11}]}')

    board = @client.val.ranked.leaderboard('a1', size: 200, start_index: 10, region: :na)

    assert_requested stub
    assert_equal 11, board['players'].first['leaderboardRank']
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

  def test_matches_accept_apac_regional
    stub = stub_request(:get, 'https://apac.api.riotgames.com/lor/match/v1/matches/by-puuid/p1/ids')
           .to_return(status: 200, headers: { 'Content-Type' => 'application/json' }, body: '["LOR2"]')

    ids = @client.lor.matches.ids_by_puuid('p1', region: :apac)

    assert_requested stub
    assert_equal ['LOR2'], ids
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

  def test_inventory_my_cards_uses_bearer_token
    stub = stub_request(:get, 'https://americas.api.riotgames.com/lor/inventory/v1/cards/me')
           .with(headers: { 'Authorization' => 'Bearer at-123' })
           .to_return(status: 200, headers: { 'Content-Type' => 'application/json' },
                      body: '[{"code":"01DE001","count":3}]')

    cards = Rito::Client.new(bearer_token: 'at-123', region: :americas,
                             rate_limiter: Rito::RateLimiting::NullLimiter.new).lor.inventory.my_cards

    assert_requested stub
    assert_equal '01DE001', cards.first['code']
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
