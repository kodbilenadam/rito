# frozen_string_literal: true

require 'dotenv/load'
require 'rito'

# Probes every testable gem endpoint with both configured API keys and
# prints a per-endpoint result matrix.
#
#   bundle exec ruby scripts/live_matrix.rb
#
# Uses RIOT_API_KEY_TEST (dev) and RIOT_API_KEY_PROD. Rate limiting is
# handled by Rito's AdaptiveLimiter; a dev key's 100 req/2 min bucket
# makes the dev pass slow on purpose (the limiter blocks, zero 429s).
#
# Fixtures are bootstrapped from a well-known account (Hide on bush#KR1).
# 404/400 count as "reachable" for probes that use synthetic ids; the
# mutating tournament POSTs are deliberately not probed, and RSO-only
# endpoints are skipped when no RIOT_RSO_TOKEN is configured.

BOOTSTRAP_GAME_NAME = 'Hide on bush'
BOOTSTRAP_TAG = 'KR1'
RSO_SKIPPED = 'SKIP (needs RSO token)'

def classify(error)
  detail = error.message.include?(': ') ? error.message.split(': ', 2)[1] : ''
  detail = detail.sub(' (check the API key: dev keys expire every 24h)', '')
  detail = " — #{detail[0, 60]}" unless detail.empty?
  case error
  when Rito::Unauthorized then "FAIL 401#{detail}"
  when Rito::Forbidden then "FAIL 403#{detail}"
  when Rito::BadRequest then "FAIL 400#{detail}"
  when Rito::MethodNotAllowed then "FAIL 405#{detail}"
  when Rito::UnsupportedMediaType then "FAIL 415#{detail}"
  when Rito::RateLimited then "FAIL 429 (retry_after=#{error.retry_after})"
  when Rito::ServiceUnavailable then 'FAIL 503'
  when Rito::ServerError then "FAIL 5xx (#{error.status})"
  when Rito::TimeoutError then 'FAIL timeout'
  when Rito::ConnectionError then 'FAIL connection'
  else "FAIL #{error.class}: #{error.message[0, 60]}"
  end
end

def run_probe(client, callable, synthetic_ok)
  result = callable.call(client)
  result.nil? ? 'ok (nil)' : 'ok'
rescue Rito::NotFound
  synthetic_ok ? 'reachable (404)' : 'FAIL 404'
rescue Rito::BadRequest
  synthetic_ok ? 'reachable (400)' : 'FAIL 400'
rescue Rito::Error => e
  classify(e)
rescue StandardError => e
  "FAIL #{e.class}: #{e.message[0, 60]}"
end

FAKE_UUID = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
FAKE_CODE = 'NA000AAAAA-INVALID'

def bootstrap(client)
  account = client.account.by_riot_id(BOOTSTRAP_GAME_NAME, BOOTSTRAP_TAG, region: :asia)
  puuid = account.puuid
  summoner_id = client.summoner.by_puuid(puuid, region: :kr).id
  match_id = client.matches.ids_by_puuid(puuid, count: 2, region: :kr).first
  champion_id = client.champion_masteries.top_for_puuid(puuid, count: 1, region: :kr)
                      &.first&.champion_id
  clash_tournament_id = client.clash.tournaments(region: :kr).first&.dig('id')
  { puuid: puuid, summoner_id: summoner_id, match_id: match_id,
    champion_id: champion_id, clash_tournament_id: clash_tournament_id }
end

def build_probes(fix)
  puuid = fix[:puuid]
  fix[:summoner_id]
  match_id = fix[:match_id]
  champion_id = fix[:champion_id]
  clash_tournament_id = fix[:clash_tournament_id]
  [

    ['account-v1 by-riot-id', ->(c) { c.account.by_riot_id(BOOTSTRAP_GAME_NAME, BOOTSTRAP_TAG, region: :asia) }, false],
    ['account-v1 by-puuid', ->(c) { c.account.by_puuid(puuid, region: :asia) }, false],
    ['account-v1 active-shard (val)', ->(c) { c.account.active_shard('val', puuid, region: :asia) }, true],
    ['account-v1 region (lol)', ->(c) { c.account.region_by_game('lol', puuid, region: :asia) }, true],
    ['summoner-v4 by-puuid', ->(c) { c.summoner.by_puuid(puuid, region: :kr) }, false],
    ['match-v5 ids-by-puuid', ->(c) { c.matches.ids_by_puuid(puuid, count: 1, region: :kr) }, false],
    ['match-v5 by-id', ->(c) { c.matches.by_id(match_id, region: :kr) }, false],
    ['match-v5 timeline-by-id', ->(c) { c.matches.timeline_by_id(match_id, region: :kr) }, false],
    ['match-v5 replays', ->(c) { c.matches.replays(puuid, region: :kr) }, true],
    ['champion-mastery for-puuid', ->(c) { c.champion_masteries.for_puuid(puuid, region: :kr) }, false],
    ['champion-mastery for+champion', lambda { |c|
      c.champion_masteries.for_puuid_and_champion(puuid, champion_id, region: :kr)
    }, false],
    ['champion-mastery top', ->(c) { c.champion_masteries.top_for_puuid(puuid, count: 1, region: :kr) }, false],
    ['champion-mastery score', ->(c) { c.champion_masteries.score(puuid, region: :kr) }, false],
    ['champion-v3 rotations', ->(c) { c.champions.rotations(region: :kr) }, false],
    ['league-v4 challenger', ->(c) { c.leagues.challenger('RANKED_SOLO_5x5', region: :kr) }, false],
    ['league-v4 grandmaster', ->(c) { c.leagues.grandmaster('RANKED_SOLO_5x5', region: :kr) }, false],
    ['league-v4 master', ->(c) { c.leagues.master('RANKED_SOLO_5x5', region: :kr) }, false],
    ['league-v4 entries-by-puuid', ->(c) { c.leagues.entries_by_puuid(puuid, region: :kr) }, true],
    ['league-v4 entries tier/div', lambda { |c|
      c.leagues.entries('RANKED_SOLO_5x5', 'DIAMOND', 'I', page: 1, region: :kr)
    }, false],
    ['league-exp-v4 entries', ->(c) { c.league_exp.entries('RANKED_SOLO_5x5', 'CHALLENGER', 'I', region: :kr) }, false],
    ['lol-status-v4 platform-data', ->(c) { c.lol_status.platform_data(region: :kr) }, false],
    ['spectator-v5 active-game', ->(c) { c.spectator.active_game(puuid, region: :kr) }, false],
    ['clash-v1 tournaments', ->(c) { c.clash.tournaments(region: :kr) }, false],
    ['clash-v1 tournament-by-id', ->(c) { c.clash.tournament(clash_tournament_id, region: :kr) }, true],
    ['clash-v1 players-by-puuid', ->(c) { c.clash.players_by_puuid(puuid, region: :kr) }, true],
    ['clash-v1 team', ->(c) { c.clash.team(1, region: :kr) }, true],
    ['clash-v1 tournament-by-team', ->(c) { c.clash.tournament_by_team(1, region: :kr) }, true],
    ['challenges config', ->(c) { c.challenges.config(region: :kr) }, false],
    ['challenges percentiles', ->(c) { c.challenges.percentiles(region: :kr) }, false],
    ['challenges challenge-config', ->(c) { c.challenges.challenge_config(101_200, region: :kr) }, false],
    ['challenges challenge-percentiles', ->(c) { c.challenges.challenge_percentiles(101_200, region: :kr) }, false],
    ['challenges leaderboard', lambda { |c|
      c.challenges.leaderboard(101_200, 'GRANDMASTER', limit: 1, region: :kr)
    }, false],
    ['challenges player-data', ->(c) { c.challenges.player_data(puuid, region: :kr) }, false],
    ['tournament-v5 code (read)', ->(c) { c.tournaments.code(FAKE_CODE, region: :americas) }, true],
    ['tournament-v5 games-by-code', ->(c) { c.tournaments.games_by_code(FAKE_CODE, region: :americas) }, true],
    ['tournament-v5 lobby-events', ->(c) { c.tournaments.lobby_events(FAKE_CODE, region: :americas) }, true],
    ['tournament-stub code (read)', ->(c) { c.tournament_stub.code(FAKE_CODE, region: :americas) }, true],
    ['tournament-stub lobby-events', ->(c) { c.tournament_stub.lobby_events(FAKE_CODE, region: :americas) }, true],
    ['tft summoner by-puuid', ->(c) { c.tft.summoner.by_puuid(puuid, region: :kr) }, true],
    ['tft leagues challenger', ->(c) { c.tft.leagues.challenger(region: :kr) }, false],
    ['tft leagues entries-by-puuid', ->(c) { c.tft.leagues.entries_by_puuid(puuid, region: :kr) }, true],
    ['tft leagues entries tier/div', ->(c) { c.tft.leagues.entries('GOLD', 'I', region: :kr) }, false],
    ['tft leagues rated-ladder', ->(c) { c.tft.leagues.rated_ladder_top('RANKED_TFT_TURBO', region: :kr) }, false],
    ['tft matches ids-by-puuid', ->(c) { c.tft.matches.ids_by_puuid(puuid, count: 1, region: :kr) }, true],
    ['tft status platform-data', ->(c) { c.tft.status.platform_data(region: :kr) }, false],
    ['tft spectator active-game', ->(c) { c.tft.spectator.active_game(puuid, region: :kr) }, false],
    ['val content', ->(c) { c.val.content.contents(region: :na) }, false],
    ['val matchlist (synthetic puuid)', ->(c) { c.val.matches.ids_by_puuid(FAKE_UUID, region: :na) }, true],
    ['val match by-id (synthetic)', ->(c) { c.val.matches.by_id(FAKE_UUID, region: :na) }, true],
    ['val recent-matches', ->(c) { c.val.matches.recent_by_queue('competitive', region: :na) }, false],
    ['val ranked leaderboard (synth)', ->(c) { c.val.ranked.leaderboard(FAKE_UUID, size: 1, region: :na) }, true],
    ['val status platform-data', ->(c) { c.val.status.platform_data(region: :na) }, false],
    ['val console matchlist', lambda { |c|
      c.val.console_matches.ids_by_puuid(FAKE_UUID, platform_type: 'xbox', region: :na)
    }, true],
    ['val console match by-id', ->(c) { c.val.console_matches.by_id(FAKE_UUID, region: :na) }, true],
    ['val console recent-matches', ->(c) { c.val.console_matches.recent_by_queue('competitive', region: :na) }, false],
    ['val console ranked', lambda { |c|
      c.val.console_ranked.leaderboard(FAKE_UUID, platform_type: 'xbox', size: 1, region: :na)
    }, true],
    ['lor ranked leaderboards', ->(c) { c.lor.ranked.leaderboards(region: :americas) }, false],
    ['lor status platform-data', ->(c) { c.lor.status.platform_data(region: :americas) }, false],
    ['lor matchlist (synthetic puuid)', ->(c) { c.lor.matches.ids_by_puuid(FAKE_UUID, region: :americas) }, true],
    ['riftbound contents', ->(c) { c.riftbound.contents(region: :americas) }, false]
  ]
end

RSO_ONLY = [
  'account-v1 me',
  'summoner-v4 me',
  'lol-rso-match ids',
  'lol-rso-match by-id',
  'lol-rso-match timeline',
  'tft summoner me',
  'lor decks my_decks',
  'lor decks create_deck',
  'lor inventory my_cards'
].freeze

def run_pass(label, client)
  puts "running #{label} pass…"
  fix = bootstrap(client)
  puts "  bootstrapped: puuid=#{fix[:puuid][0, 8]}… match=#{fix[:match_id]} " \
       "champion=#{fix[:champion_id]} clash_t=#{fix[:clash_tournament_id].inspect}"
  probes = build_probes(fix)
  results = {}
  probes.each do |name, callable, synthetic_ok|
    results[name] = run_probe(client, callable, synthetic_ok)
    print '.'
  end
  puts
  [probes, results]
rescue Rito::Unauthorized
  puts '  bootstrap got 401 — key looks expired; pass aborted'
  [{}, {}]
end

dev_client = Rito::Client.new(api_key: ENV.fetch('RIOT_API_KEY_TEST'), region: :kr)
prod_client = Rito::Client.new(api_key: ENV.fetch('RIOT_API_KEY_PROD'), region: :kr)

probes, dev_results = run_pass('dev', dev_client)
_, prod_results = run_pass('prod', prod_client)

width = probes.map { |probe| probe[0] }.map(&:length).max || 0
puts
puts format("%-#{width}s  %-18s %-18s", 'endpoint', 'dev key', 'prod key')
puts '-' * (width + 44)
probes.each do |name, _, _|
  puts format("%-#{width}s  %-18s %-18s", name, dev_results[name] || 'aborted', prod_results[name] || 'aborted')
end

ok = ->(results) { results.values.count { |value| value.start_with?('ok', 'reachable') } }
puts
puts "dev pass:  #{ok.call(dev_results)}/#{probes.size} ok/reachable, " \
     "#{dev_results.values.count { |v| v.start_with?('FAIL') }} failures"
puts "prod pass: #{ok.call(prod_results)}/#{probes.size} ok/reachable, " \
     "#{prod_results.values.count { |v| v.start_with?('FAIL') }} failures"
puts
puts "not probed (RSO bearer token only — no RIOT_RSO_TOKEN configured): #{RSO_ONLY.join(', ')}"
puts 'not probed (mutating POSTs): tournament-v5/stub create codes/provider/tournament'
