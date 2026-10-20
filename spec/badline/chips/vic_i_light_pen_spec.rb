# frozen_string_literal: true

require "spec_helper"
require "badline/vic20"

# Pinned by VIC20/split-tests/lightpen: lightpen.prg against
# dumps/dump6561e.prg and lightpen_ntsc.prg against dumps/dump6560.prg,
# 1,024 bytes each (bin/testbench --vic20 and --vic20 --ntsc).
describe Badline::Chips::VICI do
  # $9006 and $9007 after the pen goes low at +column+ of +line+.
  def latch(profile, line, column)
    vic = described_class.new(profile)
    vic.cycle! until vic.rasterline == line && vic.column == column
    vic.lightpen_level(false)
    [vic.peek(0x9006), vic.peek(0x9007)]
  end

  describe "the 6561's light pen" do
    it "latches the column plus two and the raster line" do
      expect(latch(described_class::PAL, 309, 65)).to eq([0x87, 0x9a])
    end

    it "takes the line from the cycle after the edge" do
      expect(latch(described_class::PAL, 309, 70)).to eq([0x03, 0x9b])
    end

    it "latches nothing through the last line" do
      expect(latch(described_class::PAL, 311, 1)).to eq([0, 0])
    end

    it "latches the frame's second cycle from 8 cycles before the frame" do
      expect(latch(described_class::PAL, 311, 63)).to eq([0x07, 0])
    end

    it "latches an even column 2 cycles before the frame" do
      expect(latch(described_class::PAL, 311, 69)).to eq([0x06, 0])
    end
  end

  describe "the 6560's light pen" do
    it "latches the count of the cycle after the edge" do
      expect(latch(described_class::NTSC, 260, 28)).to eq([0x3d, 0x82])
    end

    it "latches nothing while the count reads past the last line" do
      expect(latch(described_class::NTSC, 260, 29)).to eq([0, 0])
    end

    it "latches the cycle after the count turns to 0 from 8 cycles before it" do
      expect(latch(described_class::NTSC, 260, 53)).to eq([0x81, 0])
    end
  end

  describe "on the VIC-20" do
    let(:machine) { Badline::Vic20.new }

    it "latches when VIA 1 drives PA5 low" do
      machine.run_cycles(71 * 20)
      [[0x9113, 0x20], [0x9111, 0x00]].each { |address, value| machine.poke(address, value) }
      expect(machine.vic.peek(0x9006)).to eq((2 * ((machine.vic.column + 2) % 71)) + 1)
    end
  end
end
