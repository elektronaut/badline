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
