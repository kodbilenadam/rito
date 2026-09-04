# frozen_string_literal: true

require_relative 'test_helper'

class ClientTest < Minitest::Test
  def test_requires_api_key
    error = assert_raises(Rito::ConfigError) do
      Rito::Client.new(api_key: nil, bearer_token: nil)
    end
    assert_match(/api_key or bearer_token/, error.message)
  end

  def test_rejects_unknown_region
    error = assert_raises(Rito::ConfigError) do
      Rito::Client.new(api_key: 'k', region: :moon)
    end
    assert_match(/unknown region/, error.message)
  end

  def test_defaults_limiter_to_adaptive
    client = Rito::Client.new(api_key: 'k')
    assert_instance_of Rito::RateLimiting::AdaptiveLimiter, client.limiter
  end

  def test_explicit_null_limiter
    limiter = Rito::RateLimiting::NullLimiter.new
    client = Rito::Client.new(api_key: 'k', rate_limiter: limiter)
    assert_same limiter, client.limiter
  end

  def test_reads_key_from_environment
    with_config(api_key: 'env-key') do
      client = Rito::Client.new
      assert_equal 'env-key', client.api_key
    end
  end

  def test_instance_overrides_environment
    with_config(api_key: 'env-key') do
      client = Rito::Client.new(api_key: 'explicit-key')
      assert_equal 'explicit-key', client.api_key
    end
  end
end

class ModelTest < Minitest::Test
  def test_data_models_are_immutable
    account = Rito::Models::Account.from_api({ 'puuid' => 'p', 'gameName' => 'g', 'tagLine' => 't' })

    assert_raises(NoMethodError) { account.puuid = 'other' }
  end

  def test_match_model
    match = Rito::Models::Match.from_api(
      'metadata' => { 'matchId' => 'KR_1', 'participants' => %w[a b] },
      'info' => { 'gameMode' => 'CLASSIC', 'gameDuration' => 1800,
                  'participants' => [{ 'puuid' => 'a', 'championName' => 'Ahri', 'win' => true }] }
    )

    assert_equal 'KR_1', match.match_id
    assert_equal 'CLASSIC', match.info.game_mode
    assert_equal 'Ahri', match.info.participants.first.champion_name
    assert_equal %w[a b], match.metadata.participants
  end
end
