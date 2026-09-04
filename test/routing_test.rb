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
end
