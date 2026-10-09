# frozen_string_literal: true

require "minitest/autorun"
require_relative "spec_shards"

class TestSpecShards < Minitest::Test
  def setup
    times = { "spec/a_spec.rb" => 10.0, "spec/b_spec.rb" => 6.0, "spec/c_spec.rb" => 5.0 }
    @shards = SpecShards.new(%w[spec/d_spec.rb spec/c_spec.rb spec/b_spec.rb spec/a_spec.rb], times)
  end

  def test_puts_every_file_in_exactly_one_shard
    files = (1..3).flat_map { |index| @shards.shard(index, 3) }

    assert_equal %w[spec/a_spec.rb spec/b_spec.rb spec/c_spec.rb spec/d_spec.rb], files.sort
  end

  def test_balances_the_shards_by_time
    assert_equal [%w[spec/a_spec.rb spec/d_spec.rb], %w[spec/b_spec.rb spec/c_spec.rb]],
                 [@shards.shard(1, 2), @shards.shard(2, 2)]
  end

  def test_weighs_a_file_the_record_does_not_know_by_the_default
    assert_in_delta SpecShards::DEFAULT, @shards.weight("spec/d_spec.rb")
  end

  def test_refuses_a_shard_past_the_count
    assert_raises(ArgumentError) { @shards.shard(3, 2) }
  end

  def test_reads_seconds_by_file_from_a_json_report
    report = { examples: [{ file_path: "./spec/a_spec.rb", run_time: 0.25 },
                          { file_path: "./spec/a_spec.rb", run_time: 0.5 },
                          { file_path: "./spec/b_spec.rb", run_time: 1.04 }] }.to_json

    assert_equal({ "spec/a_spec.rb" => 0.8, "spec/b_spec.rb" => 1.0 }, SpecShards.times_from(report))
  end
end
