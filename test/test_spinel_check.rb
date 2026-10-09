# frozen_string_literal: true

require "minitest/autorun"
require_relative "../spinel/check"

class TestSpinelCheckMissingConstants < Minitest::Test
  def warning(name)
    "spinel: warning: uninitialized constant #{name}: defined nowhere in the program (raises NameError when reached)"
  end

  def test_names_each_missing_constant_once
    lines = [warning("Drive1541::Disk"), warning("IECBus"), warning("Drive1541::Disk")]

    assert_equal %w[Drive1541::Disk IECBus], SpinelCheck.missing_constants(lines)
  end
end

# check_sid with SpinelCheck.run replaced, so no Spinel build is needed: the
# build's output comes first for each tune, then CRuby's.
class TestSpinelCheckSid < Minitest::Test
  def output(checksum, elapsed)
    ["samples 174840 checksum #{checksum}", "timed 1500000 cycles in #{elapsed} ms, 1.0x real time"]
  end

  def check_sid(outputs)
    commands = []
    original = SpinelCheck.method(:run)
    SpinelCheck.define_singleton_method(:run) { |*command| commands << command and outputs.shift }
    capture_io { SpinelCheck.check_sid }
    commands
  ensure
    SpinelCheck.define_singleton_method(:run, original)
  end

  def test_runs_each_tune_on_the_build_and_on_cruby
    commands = check_sid([output(1, 10), output(1, 2000)] * 2)
    programs = commands.map { |command| command - ["4000000", "2500000", *SpinelCheck::SID_TUNES] }

    assert_equal [["tmp/spinel/sid"], [RbConfig.ruby, "--yjit", "-Ilib", "spinel/sid.rb"]] * 2, programs
  end

  def test_passes_each_tune_with_its_cycles
    arguments = check_sid([output(1, 10), output(1, 2000)] * 2).map { |command| command.last(3) }

    assert_equal SpinelCheck::SID_TUNES.flat_map { |tune| [["4000000", "2500000", tune]] * 2 }, arguments
  end

  def test_compares_the_samples_and_not_the_timing
    assert_equal 4, check_sid([output(1, 10), output(1, 2000), output(2, 10), output(2, 2000)]).size
  end

  def test_fails_on_a_different_checksum
    error = assert_raises(RuntimeError) { check_sid([output(1, 10), output(2, 10)]) }

    assert_match(/spinel: samples 174840 checksum 1\n.*cruby: {2}samples 174840 checksum 2/, error.message)
  end
end
