# frozen_string_literal: true

require "spec_helper"
require_relative "../../../support/keyed_oracle"

# The VDC's keyed fields against its positional save_state, which restores
# exactly: a VDC saved on any cycle, loaded into a fresh one, saves the same
# positional state, with the RAM's layout worked out from R28.
module VDCKeyedSamples
  extend KeyedOracle

  # The C128 KERNAL's 80-column setup, then a block fill, the line length
  # changed part way through a line, and the character height changed.
  SETUP = [0x7e, 0x50, 0x66, 0x49, 0x20, 0xe0, 0x19, 0x1d, 0xfc, 0xe7, 0xa0, 0xe7, 0x00, 0x00, 0x00, 0x00,
           0x00, 0x00, 0x0f, 0xe7, 0x08, 0x00, 0x78, 0xe8, 0x20, 0x47, 0xf0, 0x00, 0x2f, 0xe7, 0x4f, 0x07,
           0x00, 0x00, 0x7d, 0x64, 0xf5].freeze
  WRITES = { 100 => [[18, 0x00], [19, 0x00], [31, 0x41], [24, 0x20], [30, 0xff]],
             9_013 => [[0, 0x7a]], 20_517 => [[9, 0x0b], [28, 0x3f]], 31_000 => [[0, 0x7e], [9, 0x07]] }.freeze

  module_function

  def write(vdc, reg, value)
    vdc.poke(0xd600, reg)
    vdc.poke(0xd601, value)
  end

  def check(vdc, cycle)
    fresh = Badline::Chips::VDC.new(ram_kb: 64)
    problems = keyed_round_trip(vdc, fresh).report.lines(verbose: true)
    problems << "positional state differs" unless positional(vdc) == positional(fresh)
    problems.map { |line| "cycle #{cycle}: #{line}" }
  end

  def scripted
    @scripted ||= begin
      vdc = Badline::Chips::VDC.new(ram_kb: 64)
      SETUP.each_with_index { |value, reg| write(vdc, reg, value) }
      problems = []
      45_000.times do |cycle|
        WRITES.fetch(cycle, []).each { |reg, value| write(vdc, reg, value) }
        vdc.cycle!
        problems.concat(check(vdc, cycle)) if (cycle % 61).zero? || WRITES.keys.any? { |at| (cycle - at).abs < 30 }
      end
      problems
    end
  end
end

describe Badline::Chips::VDC::KeyedState do
  it "restores a VDC filling, changing its line length and character height" do
    expect(VDCKeyedSamples.scripted.first(5)).to be_empty
  end
end
