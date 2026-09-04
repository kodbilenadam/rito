# frozen_string_literal: true

# Records VCR cassettes against the live API.
# Run: bundle exec rake cassettes
require 'dotenv/load'
require 'vcr'
require 'rito'

VCR.configure do |config|
  config.cassette_library_dir = 'test/vcr_cassettes'
  config.hook_into :webmock
  config.filter_sensitive_data('<RIOT_API_KEY>') { ENV.fetch('RIOT_API_KEY_TEST') }
end

client = Rito::Client.new(api_key: ENV.fetch('RIOT_API_KEY_TEST'), region: :kr)

VCR.use_cassette('account_by_riot_id', record: :all) do
  account = client.account.by_riot_id('Hide on bush', 'KR1', region: :asia)
  puts "recorded account_by_riot_id: #{account.game_name}##{account.tag_line}"
end

VCR.use_cassette('summoner_by_puuid', record: :all) do
  account = client.account.by_riot_id('Hide on bush', 'KR1', region: :asia)
  summoner = client.summoner.by_puuid(account.puuid, region: :kr)
  puts "recorded summoner_by_puuid: level #{summoner.summoner_level}"
end

VCR.use_cassette('match_ids_by_puuid', record: :all) do
  account = client.account.by_riot_id('Hide on bush', 'KR1', region: :asia)
  ids = client.matches.ids_by_puuid(account.puuid, region: :asia, count: 3)
  puts "recorded match_ids_by_puuid: #{ids.size} ids"
end

VCR.use_cassette('status_platform_data', record: :all) do
  data = client.lol_status.platform_data(region: :kr)
  puts "recorded status_platform_data: #{data['id']}"
end
