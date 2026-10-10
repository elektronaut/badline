# frozen_string_literal: true

require "spec_helper"
require "badline/via/shift_register"

# Under its own clock the register drops CB1 on the first tick of a byte,
# raises it on the second, and sets the flag on the tick that raises it over
# the eighth bit. The cycle counts below are the VIC-20's via_sr testprogs'
# (see doc/pinned-behaviour.md, "VIA shift register").
describe Badline::VIA::ShiftRegister do
  subject(:sr) { described_class.new }

  # Runs the register for n cycles and returns the cycle numbers, counted
  # from 1, on which it set the flag.
  def run(cycles, underflow: true)
    flags(Array.new(cycles, underflow))
  end

  # Runs one cycle per entry, with the entry saying whether timer 2
  # underflowed on it, and returns the cycles, counted from 1, that set the
  # flag.
  def flags(underflows)
    (1..underflows.size).select { |cycle| sr.cycle!(underflows[cycle - 1]) }
  end

  # Runs one cycle per entry and returns the CB1 level after each.
  def cb1_levels(underflows)
    underflows.map do |underflow|
      sr.cycle!(underflow)
      sr.cb1_output
    end
  end

  # Runs one cycle per entry with CB2 held at that entry's level, and
  # returns the byte shifted in.
  def feed(levels, underflow: true)
    levels.each do |level|
      sr.cb2_input = level == 1
      sr.cycle!(underflow)
    end
    sr.data
  end

  # Clocks one CB1 pulse, falling then rising, into the register for each
  # bit, with CB2 at that bit's level, and returns the pulses, counted from
  # 1, whose rising edge set the flag.
  def clock_in(bits)
    (1..bits.size).select do |pulse|
      sr.cb2_input = bits[pulse - 1] == 1
      sr.cb1_edge!(false)
      sr.cb1_edge!(true)
    end
  end

  # Clocks n CB1 pulses from outside and returns CB2 after each falling edge.
  def external_bits_out(pulses)
    Array.new(pulses) do
      sr.cb1_edge!(false)
      level = sr.cb2_output ? 1 : 0
      sr.cb1_edge!(true)
      level
    end
  end

  # Collects CB2 on each falling CB1 edge the register drives itself over
  # the given number of cycles.
  def bits_out(cycles, underflow: true)
    bits = []
    cycles.times do
      before = sr.cb1_output
      sr.cycle!(underflow)
      bits << (sr.cb2_output ? 1 : 0) if before && !sr.cb1_output
    end
    bits
  end

  # Each bit of a byte, MSB first, doubled: one entry per clock half period.
  def halves(byte) = bits_of(byte).flat_map { |bit| [bit, bit] }

  def bits_of(byte) = (0..7).map { |i| (byte >> (7 - i)) & 1 }

  describe "mode 0 (disabled)" do
    it "drives neither line and ignores its clocks" do
      sr.data = 0x55
      sr.access!
      expect([run(32), sr.cb1_output, sr.cb2_output, sr.cb1_edge!(true), sr.data]).to eq([[], nil, nil, false, 0x55])
    end
  end

  describe "mode 2 (shift in under φ2)" do
    before do
      sr.mode = 2
      sr.cb2_input = true
    end

    it "idles with CB1 high and CB2 undriven" do
      expect([sr.cb1_output, sr.cb2_output]).to eq([true, nil])
    end

    it "does nothing until the data register is accessed" do
      expect([run(32), sr.data]).to eq([[], 0x00])
    end

    # Pinned by VIC20/via_sr/viasr08.
    it "drops CB1 on the second cycle after the access and raises it on the third" do
      sr.access!
      expect(cb1_levels([false] * 5)).to eq([true, false, true, false, true])
    end

    it "sets the flag on the seventeenth cycle, and only once" do
      sr.access!
      expect(run(64, underflow: false)).to eq([17])
    end

    it "shifts CB2 in on each rising edge, MSB first" do
      sr.access!
      expect(feed([0] + halves(0xa5), underflow: false)).to eq(0xa5)
    end

    it "samples CB2 as CB1 rises, not as it falls" do
      sr.access!
      expect(feed([0, 0, 1], underflow: false)).to eq(0x01)
    end

    it "leaves CB1 high once the byte is in" do
      sr.access!
      run(40)
      expect(sr.cb1_output).to be(true)
    end

    it "carries on through an access before the eighth bit" do
      sr.access!
      run(10)
      sr.access!
      expect(run(40)).to eq([7])
    end

    it "starts a new byte on an access after the flag" do
      sr.access!
      run(17)
      sr.access!
      expect(run(40)).to eq([17])
    end

    # Pinned by VIC20/via_sr/viasr08ifr.
    it "ignores an access while disabled" do
      sr.mode = 0
      sr.access!
      sr.mode = 2
      expect(run(40)).to eq([])
    end
  end

  describe "mode 1 (shift in under timer 2)" do
    before do
      sr.mode = 1
      sr.access!
    end

    it "ignores cycles without a timer 2 underflow" do
      expect([run(32, underflow: false), sr.cb1_output]).to eq([[], true])
    end

    # Pinned by VIC20/via_sr/viasr04.
    it "toggles CB1 two cycles after each underflow" do
      expect(cb1_levels([true, false, true, true, false, false])).to eq([true, true, false, false, true, false])
    end

    it "sets the flag two cycles after the sixteenth underflow" do
      expect(flags((1..51).map { |cycle| (cycle % 3).zero? })).to eq([50])
    end

    it "shifts CB2 in on each rising edge" do
      expect(feed([0, 0] + halves(0x3c))).to eq(0x3c)
    end
  end

  describe "mode 3 (shift in under external CB1)" do
    before { sr.mode = 3 }

    it "leaves CB1 and CB2 undriven" do
      expect([sr.cb1_output, sr.cb2_output]).to eq([nil, nil])
    end

    it "ignores φ2 and timer 2" do
      sr.access!
      expect([run(32), sr.data]).to eq([[], 0x00])
    end

    it "shifts CB2 in on each rising edge and flags the eighth after an access" do
      sr.access!
      expect([clock_in(bits_of(0x96)), sr.data]).to eq([[8], 0x96])
    end

    it "samples nothing on a falling edge" do
      sr.cb2_input = true
      sr.cb1_edge!(false)
      expect(sr.data).to eq(0x00)
    end

    it "keeps shifting without an access, but doesn't flag" do
      expect([clock_in(bits_of(0x81)), sr.data]).to eq([[], 0x81])
    end

    it "flags once per access" do
      sr.access!
      expect(clock_in([1] * 24)).to eq([8])
    end
  end

  describe "mode 6 (shift out under φ2)" do
    before do
      sr.mode = 6
      sr.data = 0xb4
      sr.access!
    end

    it "drives CB1 and CB2" do
      expect([sr.cb1_output, sr.cb2_output]).to eq([true, true])
    end

    # Pinned by VIC20/via_sr/viasr18.
    it "puts bit 7 on CB2 as CB1 falls on the second cycle after the access" do
      2.times { sr.cycle!(false) }
      expect([sr.cb1_output, sr.cb2_output]).to eq([false, true])
    end

    it "shifts the byte out MSB first, one bit per falling edge" do
      expect(bits_out(17, underflow: false)).to eq(bits_of(0xb4))
    end

    it "sets the flag on the seventeenth cycle" do
      expect(run(40, underflow: false)).to eq([17])
    end

    it "has the byte back in place after eight bits" do
      run(17)
      expect(sr.data).to eq(0xb4)
    end

    it "rotates bit 7 into bit 0 as each bit goes out" do
      2.times { sr.cycle!(false) }
      expect(sr.data).to eq(0x69)
    end

    it "holds CB1 high and CB2 on the last bit once done" do
      run(40)
      expect([sr.cb1_output, sr.cb2_output]).to eq([true, false])
    end
  end

  describe "mode 5 (shift out under timer 2)" do
    before do
      sr.mode = 5
      sr.data = 0x4d
      sr.access!
    end

    it "moves only on timer 2 underflows" do
      expect([run(20, underflow: false), sr.cb1_output, sr.data]).to eq([[], true, 0x4d])
    end

    it "shifts the byte out over sixteen underflows, then stops" do
      bits = bits_out(18)
      expect([bits, run(16)]).to eq([bits_of(0x4d), []])
    end

    # Pinned by VIC20/via_sr/viasr14.
    it "sets the flag two cycles after the sixteenth underflow" do
      expect(run(32)).to eq([18])
    end

    # Pinned by VIC20/via_sr/viasr14.
    it "carries on through an access before the eighth bit" do
      run(6)
      sr.access!
      expect(run(32)).to eq([12])
    end
  end

  describe "mode 4 (shift out free-running under timer 2)" do
    before do
      sr.mode = 4
      sr.data = 0xc1
    end

    it "waits for an access to start" do
      expect([run(8), sr.cb1_output]).to eq([[], true])
    end

    it "sends the byte over and over without ever flagging" do
      sr.access!
      expect([bits_out(50), run(64)]).to eq([bits_of(0xc1) * 3, []])
    end

    it "only moves on underflows" do
      sr.access!
      sr.cycle!(true)
      expect([run(8, underflow: false), sr.cb1_output]).to eq([[], false])
    end
  end

  describe "mode 7 (shift out under external CB1)" do
    before do
      sr.mode = 7
      sr.data = 0x2e
    end

    it "drives CB2 but not CB1" do
      expect([sr.cb1_output, sr.cb2_output]).to eq([nil, true])
    end

    it "ignores φ2 and timer 2" do
      sr.access!
      expect([run(32), sr.data]).to eq([[], 0x2e])
    end

    it "puts the next bit on CB2 as CB1 falls" do
      expect([external_bits_out(8), sr.data]).to eq([bits_of(0x2e), 0x2e])
    end

    it "leaves CB2 alone as CB1 rises" do
      sr.cb1_edge!(false)
      sr.cb1_edge!(true)
      expect([sr.cb2_output, sr.data]).to eq([false, 0x5c])
    end

    it "flags the eighth rising edge after an access" do
      sr.access!
      expect(clock_in([0] * 16)).to eq([8])
    end
  end

  describe "mode changes" do
    it "keeps only the mode bits" do
      sr.mode = 0x0e
      expect(sr.mode).to eq(6)
    end

    it "masks written data to a byte" do
      sr.data = 0x1ff
      expect(sr.data).to eq(0xff)
    end
  end
end
