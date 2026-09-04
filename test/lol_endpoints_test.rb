# frozen_string_literal: true

require_relative 'test_helper'

class ChampionMasteryEndpointTest < Minitest::Test
  def setup
    WebMock.reset!
    @client = Rito::Client.new(api_key: 'RGAPI-test', region: :na1,
                               rate_limiter: Rito::RateLimiting::NullLimiter.new)
  end

  def teardown
    WebMock.reset!
  end

  MASTERY = '{"puuid":"p1","championId":103,"championLevel":7,"championPoints":123456,'\
            '"championPointsUntilNextLevel":0,"championPointsSinceLastLevel":900,'\
            '"lastPlayTime":1700000000000,"tokensEarned":2,"futureField":true}'

  def test_for_puuid_maps_models
    stub_request(:get, 'https://na1.api.riotgames.com/lol/champion-mastery/v4/champion-masteries/by-puuid/p1')
      .to_return(status: 200, headers: { 'Content-Type' => 'application/json' },
                 body: "[#{MASTERY}]")

    masteries = @client.champion_masteries.for_puuid('p1')

    assert_equal 1, masteries.size
    assert_equal 103, masteries.first.champion_id
    assert_equal 7, masteries.first.champion_level
    assert_equal true, masteries.first.raw['futureField']
  end

  def test_top_for_puuid_sends_count_param
    stub = stub_request(:get, 'https://na1.api.riotgames.com/lol/champion-mastery/v4/champion-masteries/by-puuid/p1/top?count=3')
           .to_return(status: 200, headers: { 'Content-Type' => 'application/json' }, body: '[]')

    @client.champion_masteries.top_for_puuid('p1', count: 3)

    assert_requested stub
  end

  def test_score_returns_integer
    stub_request(:get, 'https://na1.api.riotgames.com/lol/champion-mastery/v4/scores/by-puuid/p1')
      .to_return(status: 200, headers: { 'Content-Type' => 'application/json' }, body: '456')

    assert_equal 456, @client.champion_masteries.score('p1')
  end
end

class LeagueEndpointTest < Minitest::Test
  def setup
    WebMock.reset!
    @client = Rito::Client.new(api_key: 'RGAPI-test', region: :na1,
                               rate_limiter: Rito::RateLimiting::NullLimiter.new)
  end

  def teardown
    WebMock.reset!
  end

  ENTRY = '{"puuid":"p1","summonerId":"s1","queueType":"RANKED_SOLO_5x5","tier":"DIAMOND",'\
          '"rank":"II","leagueId":"lg-1","leaguePoints":42,"wins":80,"losses":60,'\
          '"veteran":false,"freshBlood":true,"hotStreak":false,"inactive":false}'

  def test_entries_by_summoner_id
    stub_request(:get, 'https://na1.api.riotgames.com/lol/league/v4/entries/by-summoner/s1')
      .to_return(status: 200, headers: { 'Content-Type' => 'application/json' }, body: "[#{ENTRY}]")

    entries = @client.leagues.entries_by_summoner_id('s1')

    assert_equal 'DIAMOND', entries.first.tier
    assert_equal 'II', entries.first.rank
    assert_equal 57.14, entries.first.winrate
  end

  def test_challenger_returns_league_list
    stub_request(:get, 'https://na1.api.riotgames.com/lol/league/v4/challengerleagues/by-queue/RANKED_SOLO_5x5')
      .to_return(status: 200, headers: { 'Content-Type' => 'application/json' },
                 body: '{"leagueId":"lg-9","tier":"CHALLENGER","name":"Faker Lovers",'\
                       '"queue":"RANKED_SOLO_5x5","entries":[]}')

    list = @client.leagues.challenger('RANKED_SOLO_5x5')

    assert_equal 'Faker Lovers', list.name
    assert_empty list.entries
  end

  def test_league_exp_entries
    stub = stub_request(:get, 'https://na1.api.riotgames.com/lol/league-exp/v4/entries/RANKED_FLEX_SR/GOLD/I?page=2')
           .to_return(status: 200, headers: { 'Content-Type' => 'application/json' }, body: "[#{ENTRY}]")

    entries = @client.league_exp.entries('RANKED_FLEX_SR', 'GOLD', 'I', page: 2)

    assert_requested stub
    assert_equal 's1', entries.first.summoner_id
  end
end

class MiscLolEndpointTest < Minitest::Test
  def setup
    WebMock.reset!
    @client = Rito::Client.new(api_key: 'RGAPI-test', region: :na1,
                               rate_limiter: Rito::RateLimiting::NullLimiter.new)
  end

  def teardown
    WebMock.reset!
  end

  def test_champion_rotations
    stub_request(:get, 'https://na1.api.riotgames.com/lol/platform/v3/champion-rotations')
      .to_return(status: 200, headers: { 'Content-Type' => 'application/json' },
                 body: '{"sr":[1,2],"newplayer":[3,4]}')

    rotations = @client.champions.rotations

    assert_equal [1, 2], rotations.sr
    assert_equal [3, 4], rotations.newplayer
  end

  def test_spectator_active_game_returns_nil_on_404
    stub_request(:get, 'https://na1.api.riotgames.com/lol/spectator/v5/active-games/by-summoner-id/s1')
      .to_return(status: 404, headers: { 'Content-Type' => 'application/json' }, body: '{}')

    assert_nil @client.spectator.active_game('s1')
  end

  def test_status_platform_data
    stub_request(:get, 'https://na1.api.riotgames.com/lol/status/v4/platform-data')
      .to_return(status: 200, headers: { 'Content-Type' => 'application/json' },
                 body: '{"id":"NA1","name":"North America","locales":["en_US"],"maintenances":[],"incidents":[]}')

    data = @client.lol_status.platform_data

    assert_equal 'NA1', data['id']
  end

  def test_tournament_create_codes_posts_json_body
    stub = stub_request(:post, 'https://na1.api.riotgames.com/lol/tournament/v5/codes?count=2&tournamentId=99')
           .with(body: { 'mapType' => 'SUMMONERS_RIFT' })
           .to_return(status: 200, headers: { 'Content-Type' => 'application/json' },
                      body: '["CODE1","CODE2"]')

    codes = @client.tournaments.create_codes(tournament_id: 99, count: 2,
                                             body: { 'mapType' => 'SUMMONERS_RIFT' })

    assert_requested stub
    assert_equal %w[CODE1 CODE2], codes
  end

  def test_tournament_stub_uses_stub_path
    stub_request(:post, 'https://na1.api.riotgames.com/lol/tournament-stub/v5/providers')
      .to_return(status: 200, headers: { 'Content-Type' => 'application/json' }, body: '1234')

    assert_equal 1234, @client.tournament_stub.create_provider(body: { 'region' => 'NA', 'url' => 'https://x.dev' })
  end

  def test_challenges_leaderboard
    stub_request(:get, 'https://na1.api.riotgames.com/lol/challenges/v1/challenges/101200/leaderboards/by-level/GRANDMASTER?top=10')
      .to_return(status: 200, headers: { 'Content-Type' => 'application/json' }, body: '{"entries":[]}')

    board = @client.challenges.leaderboard(101_200, 'GRANDMASTER', top: 10)

    assert_empty board['entries']
  end

  def test_clash_tournaments
    stub_request(:get, 'https://na1.api.riotgames.com/lol/clash/v1/tournaments')
      .to_return(status: 200, headers: { 'Content-Type' => 'application/json' },
                 body: '[{"id":300,"tournamentId":300,"name":"Test"}]')

    tournaments = @client.clash.tournaments

    assert_equal 300, tournaments.first['id']
  end
end
