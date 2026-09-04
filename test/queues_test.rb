# frozen_string_literal: true

require_relative 'test_helper'

class QueuesTest < Minitest::Test
  def test_find_maps_known_queue
    queue = Rito::Queues.find(420)

    assert_equal 420, queue.id
    assert_equal 'Ranked Solo/Duo', queue.name
    assert_equal :pvp, queue.category
    assert_equal :summoners_rift, queue.mode
    assert_equal false, queue.limited_time
    assert_equal false, queue.bot_honoring_allowed
  end

  def test_bracket_alias
    assert_equal 'ARAM', Rito::Queues[450].name
  end

  def test_limited_time_flag
    assert_equal true, Rito::Queues.find(2450).limited_time
  end

  def test_bots_category
    assert_equal :bots, Rito::Queues.find(801).category
  end

  def test_unknown_and_nil_ids_return_nil
    assert_nil Rito::Queues.find(999_999)
    assert_nil Rito::Queues.find(nil)
    assert_nil Rito::Queues[nil]
  end

  def test_all_is_frozen_and_unique
    assert_equal true, Rito::Queues.all.frozen?
    assert_equal Rito::Queues.all.map(&:id).size, Rito::Queues.all.map(&:id).uniq.size
  end

  def test_enumerable
    arams = Rito::Queues.select { |queue| queue.mode == :aram }

    assert_includes arams.map(&:id), 450
    assert_equal Rito::Queues.all.size, Rito::Queues.count
  end

  def test_queue_is_immutable
    assert_raises(NoMethodError) { Rito::Queues.find(420).name = 'x' }
  end

  def test_match_info_queue_convenience
    match = Rito::Models::Match.from_api(
      'metadata' => { 'matchId' => 'NA_1', 'participants' => [] },
      'info' => { 'queueId' => 450 }
    )

    assert_equal 'ARAM', match.info.queue.name
  end
end
