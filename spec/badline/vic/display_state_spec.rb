# frozen_string_literal: true

require "spec_helper"

RSpec.describe Badline::VIC::DisplayState do
  subject(:state) { described_class.new(registers) }

  # $D011 as the KERNAL leaves it: DEN=1, RSEL=1, YSCROLL=3.
  let(:registers) { Badline::VIC::Registers.new.tap { |regs| regs.write(0x11, 0x1b) } }

  # Mirrors VIC#cycle!: the g-access runs ahead of the compare, and
  # advances the counters whenever the logic is in display state.
  def run_columns(line, columns)
    columns.each do |col|
      state.graphics_access(col) if state.display?
      state.cycle(line, col)
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
      registers.write(0x11, 0x10 | 3) # 59 & 7 == 3, so the row opens at column 17
      run_columns(59, 17..62)
    end

    it "fetches one cell less per column of delay" do
      expect(state.vmli).to eq(36) # g-accesses 18..53 rather than 14..53
    end

    it "carries the shortfall into VCBASE" do
      expect(state.vc_base).to eq(76) # 40 from the full row, 36 from this one
    end
  end

  describe "the BA to AEC gap" do
    before { advance_to(51, 12) }

    it "holds the bus off for three columns after the match" do
      expect(state.bus_taken?(12)).to be(false)
    end

    it "takes the bus three columns after the match" do
      expect(state.bus_taken?(13)).to be(true)
    end

    it "still fetches in the columns the CPU drives" do
      expect(state.fetching?(13)).to be(true)
    end
  end

  # Pinned by flibug/blackmail: its $d011 write lands in column 12
  # (Bauer cycle 14), so the match arrives in column 13 and the first three
  # c-accesses read the bus the CPU still drives.
  describe "an FLI match in column 13" do
    before do
      advance_to(52, 12)
      registers.write(0x11, 0x10 | (52 & 0b111))
      run_columns(52, 13..13)
    end

    it "keeps the bus from the CPU through column 15" do
      expect(state.bus_taken?(15)).to be(false)
    end

    it "takes the bus in column 16" do
      expect(state.bus_taken?(16)).to be(true)
    end

    it "fetches from column 13" do
      expect(state.fetching?(13)).to be(true)
    end
  end

  # Pinned by the dmadelay sweep, which the display state only lines up
  # with when the match itself opens the row.
  describe "a match mid-line" do
    before do
      advance_to(58, 55) # the first char row closes on this line
      registers.write(0x11, 0x10 | 4) # hold line 59 past its own match
      run_columns(58, 56..62)
      state.new_line(59)
      run_columns(59, 0..29)
      registers.write(0x11, 0x10 | 3)
    end

    it "is idle before the compare" do
      expect(state).to be_idle
    end

    it "enters display state in the column that matches" do
      run_columns(52, 30..30)
      expect(state).to be_display
    end
  end

  describe "a condition withdrawn mid-line" do
    before do
      advance_to(51, 20)
      registers.write(0x11, 0x10 | 4)
      run_columns(51, 21..21)
    end

    it "stops the c-accesses" do
      expect(state.fetching?(21)).to be(false)
    end

    it "stays in display state" do
      expect(state).to be_display
    end
  end

  # Pinned by colorfetchbug, whose bad lines start at Bauer cycle 17 and
  # show the last row of the cells above.
  describe "linecrunch (bad line forced after column 12)" do
    before do
      advance_to(52, 12) # through column 12 with YSCROLL still mismatched
      registers.write(0x11, 0x10 | (52 & 0b111)) # YSCROLL now matches line 52
      run_columns(52, 13..30)
    end

    it "enters display state" do
      expect(state).to be_bad_line
    end

    it "leaves the row counter unreset" do
      expect(state.rc).not_to eq(0)
    end
  end

  describe "a match standing in column 12" do
    before do
      advance_to(52, 11)
      registers.write(0x11, 0x10 | (52 & 0b111))
      run_columns(52, 12..12)
    end

    it "resets the row counter" do
      expect(state.rc).to eq(0)
    end
  end
end
