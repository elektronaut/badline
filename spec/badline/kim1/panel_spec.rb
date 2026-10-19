# frozen_string_literal: true

require "spec_helper"

# The wiring is the KIM-1 User Manual's figures 3.5 and 3.6: PB1-PB4 into
# the 74145, its outputs 0-2 the keypad's rows and 4-9 the digits, PA0-PA6
# the segments and the columns.
describe Badline::KIM1::Panel do
  subject(:panel) { described_class.new(clock) }

  let(:clock) { Struct.new(:cycles).new(0) }
  let(:rriot) { Badline::KIM1::MonitorRRIOT.new(rom: Array.new(1024, 0), peripheral: panel) }

  before do
    panel.connect(rriot)
    rriot.poke(0x03, 0x1e)
  end

  # Selects the decoder's output `output` through PB1-PB4.
  def select(output) = rriot.poke(0x02, output << 1)

  # Port A with `key` held and the decoder on `row`.
  def read_row(key, row)
    panel.press(key)
    select(row)
    rriot.peek(0x00)
  end

  # Lights `segments` on the digit at decoder output `output` from cycle
  # `from` to cycle `to`.
  def light(output, segments, from:, to:)
    clock.cycles = from
    rriot.poke(0x01, 0x7f)
    rriot.poke(0x00, segments)
    select(output)
    clock.cycles = to
    rriot.poke(0x00, 0x00)
  end

  describe "the keypad" do
    it "pulls the column of a key held in the selected row low" do
      panel.press("GO")
      select(2)
      expect(rriot.peek(0x00)).to eq(0xfd)
    end

    it "leaves the other rows alone" do
      panel.press("GO")
      select(1)
      expect(rriot.peek(0x00)).to eq(0xff)
    end

    it "puts 0 on PA6 of row 0 and D on PA0 of row 1" do
      expect([read_row("0", 0), read_row("D", 1)]).to eq([0xbf, 0xfe])
    end

    it "lets go" do
      panel.press("PC")
      panel.release
      select(2)
      expect([rriot.peek(0x00), panel.held]).to eq([0xff, nil])
    end

    it "refuses a key it doesn't have" do
      expect { panel.press("ST") }.to raise_error(ArgumentError, /ST/)
    end
  end

  describe "the TTY/KB jumper" do
    it "pulls PA0 low on output 3 when fitted" do
      panel.tty = true
      select(3)
      expect(rriot.peek(0x00)).to eq(0xfe)
    end

    it "leaves PA0 high when not" do
      select(3)
      expect(rriot.peek(0x00)).to eq(0xff)
    end
  end

  describe "the display" do
    it "shows what each digit was lit with" do
      [0x06, 0x5b, 0x4f, 0x66, 0x6d, 0x7d].each_with_index do |segments, digit|
        light(4 + digit, segments, from: digit * 1000, to: (digit * 1000) + 600)
      end
      expect(panel.display_text).to eq("1234 56")
    end

    it "takes no pattern from a digit lit for a moment" do
      light(4, 0x06, from: 0, to: 600)
      light(4, 0x7f, from: 700, to: 720)
      expect(panel.display.first).to eq(0x06)
    end

    it "goes dark once nothing lights a digit for some scans" do
      light(4, 0x06, from: 0, to: 600)
      clock.cycles = 30_000
      expect(panel.display_text).to eq("       ")
    end

    it "marks a pattern that isn't a hex digit" do
      light(9, 0x40, from: 0, to: 600)
      expect(panel.display_text).to eq("      ?")
    end

    it "lights a selected digit's seven segments while port A floats high" do
      rriot.poke(0x01, 0x00)
      select(5)
      clock.cycles = 500
      expect(panel.display[1]).to eq(0x7f)
    end
  end

  describe "#lit_cycles" do
    it "counts the cycles each segment was lit" do
      light(5, 0x03, from: 100, to: 776)
      expect(panel.lit_cycles[7, 7]).to eq([676, 676, 0, 0, 0, 0, 0])
    end

    it "counts the stretch still lit up to now" do
      light(4, 0x01, from: 0, to: 100)
      rriot.poke(0x00, 0x01)
      clock.cycles = 150
      expect(panel.lit_cycles.first).to eq(150)
    end

    it "starts again from zero" do
      light(4, 0x01, from: 0, to: 100)
      panel.lit_cycles
      expect(panel.lit_cycles.sum).to eq(0)
    end
  end
end
