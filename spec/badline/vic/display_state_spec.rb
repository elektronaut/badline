# frozen_string_literal: true

require "spec_helper"

RSpec.describe Badline::VIC::DisplayState do
  subject(:state) { described_class.new(registers) }

  # Default $D011 is 0x1b: DEN=1, RSEL=1, YSCROLL=3.
  let(:registers) { Badline::VIC::Registers.new }

  # Mirrors VIC#cycle!: the g-access columns advance the counters whenever
  # the logic is in display state.
  def run_columns(line, columns)
    columns.each do |col|
      state.cycle(line, col)
      state.graphics_access if state.display? && (16..55).cover?(col)
    end
  end

  def run_line(line, up_to: 62)
    state.new_frame if line.zero?
    state.new_line(line)
    run_columns(line, 0..up_to)
  end

  def advance_to(line, column)
    (0...line).each { |prev| run_line(prev) }
    run_line(line, up_to: column)
  end

  describe "bad lines" do
    it "enters display state on the first bad line" do
      advance_to(51, 30) # 51 & 7 == 3 == YSCROLL
      expect(state).to be_display
    end

    it "resets the row counter on the bad line" do
      advance_to(51, 30)
      expect(state.rc).to eq(0)
    end

    it "flags the line as a bad line" do
      advance_to(51, 30)
      expect(state).to be_bad_line
    end

    it "is not a bad line when YSCROLL does not match" do
      advance_to(52, 30) # 52 & 7 == 4 != 3
      expect(state).not_to be_bad_line
    end
  end

  describe "the row counter" do
    it "increments on each line within the char row" do
      advance_to(53, 30) # bad line 51 -> RC 0, then +1 per line
      expect(state.rc).to eq(2)
    end

    it "holds VCBASE within the first char row" do
      advance_to(57, 30)
      expect(state.vc_base).to eq(0)
    end

    it "advances VCBASE by 40 at the next char row" do
      advance_to(59, 30) # one char row down (the next bad line)
      expect(state.vc_base).to eq(40)
    end
  end

  describe "the DEN-at-$30 latch" do
    before { registers.write(0x11, 0x03) } # DEN=0, YSCROLL=3 from power-on

    it "stays idle when DEN was clear during line $30" do
      advance_to(51, 30)
      expect(state).to be_idle
    end

    it "produces no bad lines" do
      advance_to(51, 30)
      expect(state).not_to be_bad_line
    end
  end

  describe "FLD (bad lines withheld)" do
    before do
      advance_to(51, 62) # establish display on the first bad line
      (52..62).each do |line|
        registers.write(0x11, 0x10 | ((line + 4) & 0b111)) # matches neither this line nor the next
        run_line(line)
      end
    end

    it "falls back to idle once the row counter wraps" do
      expect(state).to be_idle
    end

    it "stops advancing VCBASE" do
      expect(state.vc_base).to eq(40) # only the single pre-FLD char row advanced
    end
  end

  describe "a row opened inside the fetch window" do
    before do
      advance_to(58, 55) # the first char row closes on this line, RC at 7
      registers.write(0x11, 0x10 | 4) # hold line 59 past its own match
      run_columns(58, 56..62)
      state.new_line(59)
      run_columns(59, 0..16)
      registers.write(0x11, 0x10 | 3) # 59 & 7 == 3, so the row opens at column 20
      run_columns(59, 17..62)
    end

    it "fetches one cell less per column of delay" do
      expect(state.vmli).to eq(36) # g-accesses 20..55 rather than 16..55
    end

    it "carries the shortfall into VCBASE" do
      expect(state.vc_base).to eq(76) # 40 from the full row, 36 from this one
    end
  end

  describe "the BA to AEC gap" do
    before { advance_to(51, 14) }

    it "holds the bus off for three columns after the match" do
      expect(state.bus_taken?(14)).to be(false)
    end

    it "takes the bus three columns after the match" do
      expect(state.bus_taken?(15)).to be(true)
    end

    it "still fetches in the columns the CPU drives" do
      expect(state.fetching?(15)).to be(true)
    end
  end

  describe "linecrunch (bad line forced after cycle 14)" do
    before do
      advance_to(52, 14) # through cycle 14 with YSCROLL still mismatched
      registers.write(0x11, 0x10 | (52 & 0b111)) # YSCROLL now matches line 52
      run_columns(52, 15..30)
    end

    it "enters display state" do
      expect(state).to be_bad_line
    end

    it "leaves the row counter unreset" do
      expect(state.rc).not_to eq(0)
    end
  end
end
