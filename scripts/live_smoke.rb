# frozen_string_literal: true

require 'dotenv/load'
require 'rito'

api_key = ENV.fetch('RIOT_API_KEY_TEST')
client = Rito::Client.new(api_key: api_key, region: :kr)

puts '== account-v1 =='
account = client.account.by_riot_id('Hide on bush', 'KR1', region: :asia)
puts "#{account.game_name}##{account.tag_line}  puuid: #{account.puuid[0, 12]}..."

puts
puts '== summoner-v4 =='
summoner = client.summoner.by_puuid(account.puuid, region: :kr)
puts "level: #{summoner.summoner_level}"

puts
puts '== champion-mastery-v4 =='
top = client.champion_masteries.top_for_puuid(account.puuid, count: 3, region: :kr)
top.each { |m| puts "champion #{m.champion_id}: level #{m.champion_level}, #{m.champion_points} pts" }
puts "total score: #{client.champion_masteries.score(account.puuid, region: :kr)}"

puts
puts '== champion-v3 rotations =='
rot = client.champions.rotations(region: :kr)
puts "free champs (sr): #{rot.sr.first(5).inspect}..."

puts
puts '== league-v4 (entries by puuid flow needs summonerId; using challenger ladder) =='
ladder = client.leagues.challenger('RANKED_SOLO_5x5', region: :kr)
puts "challenger league: #{ladder.name}, #{ladder.entries.size} players"

puts
puts '== league-exp-v4 =='
entries = client.league_exp.entries('RANKED_SOLO_5x5', 'CHALLENGER', 'I', page: 1, region: :kr)
first = entries.first
puts "top entry: #{first.tier} #{first.rank}, #{first.league_points} LP" if first

puts
puts '== lol-status-v4 =='
status = client.lol_status.platform_data(region: :kr)
puts "id: #{status['id']}, incidents: #{status['incidents'].size}"

puts
puts '== spectator-v5 =='
begin
  game = client.spectator.active_game(summoner.id, region: :kr)
  puts game ? "in game: #{game['gameMode']}" : 'not in game (nil)'
rescue Rito::Forbidden
  puts '403 Forbidden — spectator endpoints need a production key'
end

puts
puts '== rate limit burst: 30 requests against the 20 req/s key =='
started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
30.times { client.summoner.by_puuid(account.puuid, region: :kr) }
elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
puts "took #{elapsed.round(2)}s, zero 429s"
