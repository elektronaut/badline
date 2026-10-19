# frozen_string_literal: true

require "minitest/autorun"
require "badline/chips/m6809"
require_relative "support/m6809_code_tester"

# reyco2000's 6809 test programs on a bare 6809: every documented
# instruction and flag, IRQ, FIRQ and NMI with SYNC and CWAI, and the
# datasheet's cycle counts. Each reports through its test device.
class TestM6809CodeTester < Minitest::Test
  M6809CodeTester::PROGRAMS.each do |name|
    define_method("test_#{name}") do
      code, console, pc, cycles = M6809CodeTester.run(Badline::Chips::M6809, name)

      assert_equal 0, code, format("%<console>s\nstopped at PC $%<pc>04x after %<cycles>d cycles",
                                   console:, pc:, cycles:)
    end
  end
end
