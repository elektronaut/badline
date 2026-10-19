# frozen_string_literal: true

require "spec_helper"
require "badline/vic20"

describe Badline::Chips::VICI do
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

  describe "the 6560's raster" do
    subject(:vic) { described_class.new(described_class::NTSC) }

    def count = (vic.peek(0x9004) << 1) | (vic.peek(0x9003) >> 7)

    # The count after +cycles+, and again a cycle later.
    def counts_after(cycles)
      run(cycles)
      before = count
      run(1)
      [before, count]
    end

    it "moves to the next line after 65 cycles" do
      run(65)
      expect([vic.rasterline, vic.column]).to eq([1, 0])
    end

    it "wraps to line 0 after 261 lines" do
      run(65 * 261)
      expect(vic.rasterline).to eq(0)
    end

    it "counts the next line from 28 cycles in" do
      expect(counts_after((65 * 9) + 27)).to eq([9, 10])
    end

    it "counts one past the last line on the last line, then 0 from 61 cycles in" do
      expect(counts_after((65 * 260) + 60)).to eq([261, 0])
    end

    context "with $9000 bit 7 set, interlaced" do
      before { vic.poke(0x9000, 0x80) }

      # The lines in each of the next +frames+ frames.
      def frame_lengths(frames)
        Array.new(frames) do
          lines = 0
          loop do
            run(65)
            lines += 1
            break if vic.rasterline.zero?
          end
          lines
        end
      end

      it "alternates 263- and 262-line fields from the next frame on, the long one first" do
        expect(frame_lengths(5)).to eq([261, 263, 262, 263, 262])
      end

      it "goes back to 261 lines from the frame after bit 7 is cleared" do
        run(65 * (261 + 100))
        vic.poke(0x9000, 0x00)
        expect(frame_lengths(3)).to eq([263 - 100, 261, 261])
      end

      it "wraps the count to 0 on the long field's last line where it would move on" do
        expect(counts_after((65 * (261 + 262)) + 27)).to eq([262, 0])
      end

      it "counts 262 on the short field's last line, then 0 from 61 cycles in" do
        expect(counts_after((65 * (261 + 263 + 261)) + 60)).to eq([262, 0])
      end
    end
  end

  describe "the 6561's raster with $9000 bit 7 set" do
    it "stays 312 lines a frame" do
      vic.poke(0x9000, 0x80)
      run(71 * 312 * 2)
      expect([vic.rasterline, vic.column]).to eq([0, 0])
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
