# frozen_string_literal: true

require "minitest/autorun"
require_relative "../spinel/sidtests_check"

class TestSpinelSIDTestsBalance < Minitest::Test
  TESTS = { "a" => 10, "b" => 40, "c" => 20, "d" => 30 }.freeze

  def test_the_shards_share_the_budget
    assert_equal([50, 50], SpinelSIDTests.balance(TESTS, 2).map { it.values.sum })
  end

  def test_each_shard_keeps_the_test_order
    assert_equal [%w[a b], %w[c d]], SpinelSIDTests.balance(TESTS, 2).map(&:keys).sort
  end

  def test_there_are_no_more_shards_than_tests
    assert_equal 4, SpinelSIDTests.balance(TESTS, 8).length
  end
end
