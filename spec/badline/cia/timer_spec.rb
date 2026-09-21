# frozen_string_literal: true

require "spec_helper"

# The init latch and the two control writes of each `(*1)` case, keyed by the
# test number the suite prints.
LORENZ_STAR_CASES = { 0x05 => [1, 0x10, 0x11], 0x07 => [1, 0x10, 0x19],
                      0x0d => [12, 0x11, 0x11], 0x0f => [12, 0x11, 0x19],
                      0x15 => [1, 0x18, 0x11], 0x17 => [1, 0x18, 0x19],
                      0x1d => [12, 0x19, 0x11], 0x1f => [12, 0x19, 0x19] }.freeze

# The Lorenz cia1ta/cia1tb tests force a load through the control register
# and read the counter, ICR and control register back, four cycles apart.
# Their `(*1)` cases are the ones the suite marks as differing between chip
# revisions, and the difference is in the ICR alone: the 6526 raises IR one
# cycle after the source flag, so a read landing on the flag's own cycle
# still sees the source bit by itself, while the 6526A already has bit 7 up.
# Badline models the 6526, which is what Lorenz.d81 expects.
describe Badline::CIA::Timer do
  subject(:cia) { Badline::CIA.new(start: 0xdc00) }

  let(:timer_a) { { latch: 0xdc04, latch_high: 0xdc05, control: 0xdc0e, mask: 0x81 } }
  let(:timer_b) { { latch: 0xdc06, latch_high: 0xdc07, control: 0xdc0f, mask: 0x82 } }

  # Replays the suite's inner loop at the cycle offsets its instruction
  # stream lands on, counted from the first latch write: force load at 6,
  # ICR acknowledge at 10, the "init" control write at 14, the latch again
  # at 22, the "before" control write at 26, then the counter, ICR and
  # control reads at 30, 34 and 38.
  def replay(regs, test, next_latch:)
    init_latch, init_control, next_control = LORENZ_STAR_CASES[test]
    cia.poke(0xdc0d, 0x7f)
    cia.poke(0xdc0d, regs[:mask])
    cia.poke(regs[:latch_high], 0x00)
    reads = []
    39.times do |cycle|
      cia.cycle!
      case cycle
      when 0 then cia.poke(regs[:latch], init_latch)
      when 6 then cia.poke(regs[:control], 0x10)
      when 10 then cia.peek(0xdc0d)
      when 14 then cia.poke(regs[:control], init_control)
      when 22 then cia.poke(regs[:latch], next_latch)
      when 26 then cia.poke(regs[:control], next_control)
      when 30 then reads << cia.peek(regs[:latch])
      when 34 then reads << cia.peek(0xdc0d)
      when 38 then reads << cia.peek(regs[:control])
      end
    end
    reads
  end

  describe "the (*1) interrupt readback (6526, not 6526A)" do
    LORENZ_STAR_CASES.each_key do |test|
      it "reads timer A's flag without IR in cia1ta test ##{format('%02x', test)}" do
        expect(replay(timer_a, test, next_latch: 5)[1]).to eq(0x01)
      end

      it "reads timer B's flag without IR in cia1tb test ##{format('%02x', test)}" do
        expect(replay(timer_b, test, next_latch: 5)[1]).to eq(0x02)
      end
    end
  end

  describe "the counter over the underflow in those cases" do
    LORENZ_STAR_CASES.each_key do |test|
      it "reads back the reloaded latch, never zero, in cia1ta test ##{format('%02x', test)}" do
        expect(replay(timer_a, test, next_latch: 1)[0]).to eq(0x01)
      end
    end
  end
end
