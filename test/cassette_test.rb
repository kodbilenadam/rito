# frozen_string_literal: true

require_relative 'test_helper'

# Plays back live-recorded cassettes (bundle exec rake cassettes).
class CassetteTest < Minitest::Test
  def setup
    @client = Rito::Client.new(api_key: 'RGAPI-cassette', region: :kr,
                               rate_limiter: Rito::RateLimiting::NullLimiter.new)
  end

  def test_account_by_riot_id
    VCR.use_cassette('account_by_riot_id') do
      account = @client.account.by_riot_id('Hide on bush', 'KR1', region: :asia)
      assert_equal 'Hide on bush', account.game_name
      assert_equal 'KR1', account.tag_line
      assert_match(/\A[\w-]{70,}\z/, account.puuid)
    end
  end

  def test_summoner_by_puuid
    VCR.use_cassette('account_by_riot_id') do
      VCR.use_cassette('summoner_by_puuid') do
        account = @client.account.by_riot_id('Hide on bush', 'KR1', region: :asia)
        summoner = @client.summoner.by_puuid(account.puuid, region: :kr)
        assert_equal account.puuid, summoner.puuid
        assert summoner.summoner_level > 100
      end
    end
  end

  def test_match_ids_by_puuid
    VCR.use_cassette('account_by_riot_id') do
      VCR.use_cassette('match_ids_by_puuid') do
        account = @client.account.by_riot_id('Hide on bush', 'KR1', region: :asia)
        ids = @client.matches.ids_by_puuid(account.puuid, region: :asia, count: 3)
        assert_kind_of Array, ids
        assert ids.size <= 3
      end
    end
  end

  def test_status_platform_data
    VCR.use_cassette('status_platform_data') do
      data = @client.lol_status.platform_data(region: :kr)
      assert_equal 'KR', data['id']
      assert_equal 'Korea', data['name']
      assert_kind_of Array, data['incidents']
    end
  end
end
