# frozen_string_literal: true

require "spec_helper"
require "badline/vic20"

describe Badline::Vic20::VIC do
  subject(:vic) { described_class.new }

  def run(cycles)
    cycles.times { vic.cycle! }
  end

  describe "the raster" do
    it "moves to the next line after 71 cycles" do
      run(71)
      expect([vic.rasterline, vic.column]).to eq([1, 0])
    end

    it "wraps to line 0 after 312 lines" do
      run(71 * 312)
      expect(vic.rasterline).to eq(0)
    end

    it "reads bits 8-1 of the line at $9004" do
      run(71 * 311)
      expect(vic.peek(0x9004)).to eq(155)
    end

    it "reads bit 0 of the line at $9003 bit 7" do
      run(71 * 311)
      expect(vic.peek(0x9003)).to eq(0x80)
    end

    it "keeps $9003's other bits as written" do
      vic.poke(0x9003, 0xae)
      expect(vic.peek(0x9003)).to eq(0x2e)
    end
  end

  describe "the registers" do
    it "read back what was written" do
      vic.poke(0x900f, 0x1b)
      expect(vic.peek(0x900f)).to eq(0x1b)
    end

    it "repeat every sixteen bytes" do
      vic.poke(0x9025, 0xf0)
      expect(vic.peek(0x90f5)).to eq(0xf0)
    end

    it "read no light pen" do
      vic.poke(0x9006, 0x12)
      expect([vic.peek(0x9006), vic.peek(0x9007)]).to eq([0, 0])
    end

    it "read the pots as $FF with nothing plugged in" do
      vic.poke(0x9008, 0x12)
      expect([vic.peek(0x9008), vic.peek(0x9009)]).to eq([0xff, 0xff])
    end

    it "are all written as the register file" do
      vic.poke(0x9004, 0x19)
      expect(vic.register_file[4]).to eq(0x19)
    end
  end

  describe "#power_on!" do
    it "clears the registers and puts the raster at the top" do
      vic.poke(0x900f, 0x1b)
      run(100)
      vic.power_on!
      expect([vic.register_file.uniq, vic.rasterline, vic.column]).to eq([[0], 0, 0])
    end
  end
end
