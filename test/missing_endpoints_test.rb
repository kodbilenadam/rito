# frozen_string_literal: true

require_relative 'test_helper'

class RsoMatchEndpointTest < Minitest::Test
  def setup
    WebMock.reset!
    @client = Rito::Client.new(bearer_token: 'at-123', region: :americas,
                               rate_limiter: Rito::RateLimiting::NullLimiter.new)
  end

  def teardown
    WebMock.reset!
  end

  def test_ids_sends_bearer_token_and_params
    stub = stub_request(:get, 'https://americas.api.riotgames.com/lol/rso-match/v1/matches/ids?count=5&start=0')
           .with(headers: { 'Authorization' => 'Bearer at-123' })
           .to_return(status: 200, headers: { 'Content-Type' => 'application/json' }, body: '["RSO_1"]')

    ids = @client.rso_matches.ids(count: 5, start: 0)

    assert_requested stub
    assert_equal ['RSO_1'], ids
  end

  def test_by_id_maps_match_model
    stub_request(:get, 'https://asia.api.riotgames.com/lol/rso-match/v1/matches/KR_1')
      .to_return(status: 200, headers: { 'Content-Type' => 'application/json' },
                 body: '{"metadata":{"matchId":"KR_1","participants":["p1"]},"info":{}}')

    match = @client.rso_matches.by_id('KR_1', region: :kr)

    assert_equal 'KR_1', match.match_id
  end

  def test_timeline_by_id
    stub = stub_request(:get, 'https://europe.api.riotgames.com/lol/rso-match/v1/matches/EU_1/timeline')
           .to_return(status: 200, headers: { 'Content-Type' => 'application/json' }, body: '{"info":{}}')

    timeline = @client.rso_matches.timeline_by_id('EU_1', region: :europe)

    assert_requested stub
    assert_equal({}, timeline['info'])
  end
end

class MatchReplaysEndpointTest < Minitest::Test
  def setup
    WebMock.reset!
    @client = Rito::Client.new(api_key: 'RGAPI-test', region: :americas,
                               rate_limiter: Rito::RateLimiting::NullLimiter.new)
  end

  def teardown
    WebMock.reset!
  end

  def test_replays_maps_model
    stub = stub_request(:get, 'https://americas.api.riotgames.com/lol/match/v5/matches/by-puuid/p1/replays')
           .to_return(status: 200, headers: { 'Content-Type' => 'application/json' },
                      body: '{"total":2,"matchFileURLs":["https://replay/1","https://replay/2"]}')

    replay = @client.matches.replays('p1')

    assert_requested stub
    assert_equal 2, replay.total
    assert_equal ['https://replay/1', 'https://replay/2'], replay.match_file_urls
  end
end

class NewLolEndpointsTest < Minitest::Test
  def setup
    WebMock.reset!
    @client = Rito::Client.new(api_key: 'RGAPI-test', region: :na1,
                               rate_limiter: Rito::RateLimiting::NullLimiter.new)
  end

  def teardown
    WebMock.reset!
  end

  def test_summoner_me_uses_bearer_token
    stub = stub_request(:get, 'https://na1.api.riotgames.com/lol/summoner/v4/summoners/me')
           .with(headers: { 'Authorization' => 'Bearer at-123' })
           .to_return(status: 200, headers: { 'Content-Type' => 'application/json' },
                      body: '{"id":"s1","puuid":"p1","name":"me","summonerLevel":30}')

    summoner = Rito::Client.new(bearer_token: 'at-123', region: :na1,
                                rate_limiter: Rito::RateLimiting::NullLimiter.new).summoner.me

    assert_requested stub
    assert_equal 'me', summoner.name
  end

  def test_clash_tournament_by_id
    stub = stub_request(:get, 'https://na1.api.riotgames.com/lol/clash/v1/tournaments/300')
           .to_return(status: 200, headers: { 'Content-Type' => 'application/json' },
                      body: '{"id":300,"name":"Clash"}')

    tournament = @client.clash.tournament(300)

    assert_requested stub
    assert_equal 'Clash', tournament['name']
  end

  def test_challenges_challenge_config_and_percentiles
    config_stub = stub_request(:get, 'https://na1.api.riotgames.com/lol/challenges/v1/challenges/101200/config')
                  .to_return(status: 200, headers: { 'Content-Type' => 'application/json' }, body: '{"id":101200}')
    percentiles_stub = stub_request(:get, 'https://na1.api.riotgames.com/lol/challenges/v1/challenges/101200/percentiles')
                       .to_return(status: 200, headers: { 'Content-Type' => 'application/json' },
                                  body: '{"GRANDMASTER":0.02,"CHALLENGER":0.01}')

    assert_equal 101_200, @client.challenges.challenge_config(101_200)['id']
    assert_equal 0.01, @client.challenges.challenge_percentiles(101_200)['CHALLENGER']
    assert_requested config_stub
    assert_requested percentiles_stub
  end

  def test_tournament_games_by_code
    stub = stub_request(:get, 'https://na1.api.riotgames.com/lol/tournament/v5/games/by-code/CODE1')
           .to_return(status: 200, headers: { 'Content-Type' => 'application/json' },
                      body: '[{"gameId":42}]')

    games = @client.tournaments.games_by_code('CODE1')

    assert_requested stub
    assert_equal 42, games.first['gameId']
  end
end

class NewTftEndpointsTest < Minitest::Test
  def setup
    WebMock.reset!
    @client = Rito::Client.new(api_key: 'RGAPI-test', region: :na1,
                               rate_limiter: Rito::RateLimiting::NullLimiter.new)
  end

  def teardown
    WebMock.reset!
  end

  def test_league_entries_by_puuid
    stub = stub_request(:get, 'https://na1.api.riotgames.com/tft/league/v1/by-puuid/p1')
           .to_return(status: 200, headers: { 'Content-Type' => 'application/json' },
                      body: '[{"puuid":"p1","tier":"GOLD","rank":"I"}]')

    entries = @client.tft.leagues.entries_by_puuid('p1')

    assert_requested stub
    assert_equal 'GOLD', entries.first['tier']
  end

  def test_league_entries_by_tier_division
    stub = stub_request(:get, 'https://na1.api.riotgames.com/tft/league/v1/entries/GOLD/I?queue=RANKED_TFT_TURBO&page=2')
           .to_return(status: 200, headers: { 'Content-Type' => 'application/json' }, body: '[]')

    @client.tft.leagues.entries('GOLD', 'I', queue: 'RANKED_TFT_TURBO', page: 2)

    assert_requested stub
  end

  def test_league_rejects_regional_routing
    assert_raises(ArgumentError) do
      @client.tft.leagues.challenger(region: :americas)
    end
  end
end

class ValorantConsoleRankedTest < Minitest::Test
  def setup
    WebMock.reset!
    @client = Rito::Client.new(api_key: 'RGAPI-test', region: :na1,
                               rate_limiter: Rito::RateLimiting::NullLimiter.new)
  end

  def teardown
    WebMock.reset!
  end

  def test_leaderboard_requires_platform_type
    stub = stub_request(:get, 'https://na.api.riotgames.com/val/console/ranked/v1/leaderboards/by-act/a1?platformType=xbox')
           .to_return(status: 200, headers: { 'Content-Type' => 'application/json' },
                      body: '{"players":[]}')

    board = @client.val.console_ranked.leaderboard('a1', platform_type: 'xbox', region: :na)

    assert_requested stub
    assert_empty board['players']
  end

  def test_accepts_console_br_platform_for_matches
    stub = stub_request(:get, 'https://br.api.riotgames.com/val/console/match/v1/matches/M1')
           .to_return(status: 200, headers: { 'Content-Type' => 'application/json' }, body: '{}')

    @client.val.console_matches.by_id('M1', region: :br)

    assert_requested stub
  end

  def test_rejects_lol_platform_for_console_ranked
    assert_raises(ArgumentError) do
      @client.val.console_ranked.leaderboard('a1', platform_type: 'xbox', region: :na1)
    end
  end
end

class LorCreateDeckTest < Minitest::Test
  def setup
    WebMock.reset!
  end

  def teardown
    WebMock.reset!
  end

  def test_create_deck_posts_body_and_returns_id
    rso_client = Rito::Client.new(bearer_token: 'at-123', region: :americas,
                                  rate_limiter: Rito::RateLimiting::NullLimiter.new)
    stub = stub_request(:post, 'https://americas.api.riotgames.com/lor/deck/v1/decks/me')
           .with(headers: { 'Authorization' => 'Bearer at-123' },
                 body: '{"name":"My Deck","cards":{"01DE001":3}}')
           .to_return(status: 200, headers: { 'Content-Type' => 'application/json' }, body: '"deck-id-1"')

    deck_id = rso_client.lor.decks.create_deck(body: { 'name' => 'My Deck', 'cards' => { '01DE001' => 3 } })

    assert_requested stub
    assert_equal 'deck-id-1', deck_id
  end
end
