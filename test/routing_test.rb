# frozen_string_literal: true

require_relative 'test_helper'

class RoutingTest < Minitest::Test
  def test_platform_host
    assert_equal 'na1.api.riotgames.com', Rito::Routing.host_for(:na1)
    assert_equal 'kr.api.riotgames.com', Rito::Routing.host_for('KR')
  end

  def test_regional_host
    assert_equal 'americas.api.riotgames.com', Rito::Routing.host_for(:americas)
    assert_equal 'sea.api.riotgames.com', Rito::Routing.host_for('SEA')
  end

  def test_unknown_routing_value_raises
    assert_raises(ArgumentError) { Rito::Routing.host_for(:moon1) }
  end

  def test_resolve_platform_accepts_platform
    assert_equal 'na1', Rito::Routing.resolve(:platform, :na1)
  end

  def test_resolve_platform_rejects_regional
    assert_raises(ArgumentError) { Rito::Routing.resolve(:platform, :americas) }
  end

  def test_resolve_regional_accepts_regional
    assert_equal 'europe', Rito::Routing.resolve(:regional, :europe)
  end

  def test_resolve_regional_escalates_platform
    assert_equal 'americas', Rito::Routing.resolve(:regional, :na1)
    assert_equal 'asia', Rito::Routing.resolve(:regional, :kr)
    assert_equal 'europe', Rito::Routing.resolve(:regional, :euw1)
  end

  def test_regional_for_account_normalizes_sea
    assert_equal 'asia', Rito::Routing.regional_for_account(:sea)
    assert_equal 'americas', Rito::Routing.regional_for_account(:americas)
    assert_equal 'americas', Rito::Routing.regional_for_account(:na1)
  end

  def test_pbe1_is_a_platform_and_me1_escalates_to_europe
    assert_equal 'pbe1.api.riotgames.com', Rito::Routing.host_for(:pbe1)
    assert_equal 'europe', Rito::Routing.resolve(:regional, :me1)
  end

  def test_dead_platforms_are_rejected
    %i[ph2 th2].each do |value|
      assert_raises(ArgumentError) { Rito::Routing.host_for(value) }
      assert_raises(ArgumentError) { Rito::Routing.resolve(:platform, value) }
    end
  end

  def test_esports_regionals_are_valid
    assert_equal 'esports.api.riotgames.com', Rito::Routing.host_for(:esports)
    assert_equal 'esportseu.api.riotgames.com', Rito::Routing.host_for(:esportseu)
    assert_equal 'esports', Rito::Routing.resolve(:regional, :esports)
  end

  def test_apac_is_a_valid_regional
    assert_equal 'apac.api.riotgames.com', Rito::Routing.host_for(:apac)
    assert_equal 'apac', Rito::Routing.resolve(:regional, :apac)
  end

  def test_resolve_valorant_platform
    assert_equal 'na', Rito::Routing.resolve(:valorant_platform, :na)
    assert_equal 'kr', Rito::Routing.resolve(:valorant_platform, 'KR')
    assert_equal 'esports', Rito::Routing.resolve(:valorant_platform, :esports)
  end

  def test_resolve_valorant_platform_rejects_lol_and_dead_platforms
    assert_raises(ArgumentError) { Rito::Routing.resolve(:valorant_platform, :na1) }
    assert_raises(ArgumentError) { Rito::Routing.resolve(:valorant_platform, :ph2) }
  end

  def test_resolve_valorant_console_platform_accepts_br_and_latam
    assert_equal 'br', Rito::Routing.resolve(:valorant_console_platform, :br)
    assert_equal 'latam', Rito::Routing.resolve(:valorant_console_platform, :latam)
  end

  def test_resolve_valorant_console_platform_rejects_lol_platforms
    assert_raises(ArgumentError) { Rito::Routing.resolve(:valorant_console_platform, :na1) }
    assert_raises(ArgumentError) { Rito::Routing.resolve(:valorant_console_platform, :kr) }
  end
end
