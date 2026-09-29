# frozen_string_literal: true

require "spec_helper"

describe Badline::Region do
  def blanked(count, span) = (0...count).select { |position| described_class.blanked?(position, span) }

  describe "PAL" do
    subject(:region) { described_class::PAL }

    it "clocks the 6569's 63 cycles by 312 lines at 985,248 Hz" do
      expect([region.clock_hz, region.cycles_per_line, region.lines_per_frame]).to eq([985_248, 63, 312])
    end

    it "blanks columns 61 to 9, wrapping past the end of the line" do
      expect(blanked(63, region.hblank)).to eq([*0..9, 61, 62])
    end

    it "blanks lines 300 to 15, wrapping past the end of the frame" do
      expect(blanked(312, region.vblank)).to eq([*0..15, *300..311])
    end

    it "crops 384 by 272 from column 96 of line 20" do
      expect(region.crop).to eq([96, 20, 384, 272])
    end

    it "runs on 50 Hz mains" do
      expect(region.mains_hz).to eq(50)
    end
  end

  describe "NTSC" do
    subject(:region) { described_class::NTSC }

    it "clocks the 6567R8's 65 cycles by 263 lines at 1,022,727 Hz" do
      expect([region.clock_hz, region.cycles_per_line, region.lines_per_frame]).to eq([1_022_727, 65, 263])
    end

    it "blanks the lines VICE's NTSC view leaves out, 12 to 27" do
      expect(blanked(263, region.vblank)).to eq([*12..27])
    end

    it "crops 384 by 235 from column 96 of line 28" do
      expect(region.crop).to eq([96, 28, 384, 235])
    end

    it "fetches sprite 0 in cycle 59 and turns its display on in cycle 59" do
      expect([region.sprite_cycle, region.sprite_display_cycle]).to eq([59, 59])
    end

    it "holds the X counter for 8 pixels" do
      expect(region.x_hold).to eq(8)
    end

    it "runs on 60 Hz mains" do
      expect(region.mains_hz).to eq(60)
    end
  end

  describe "NTSC_OLD" do
    subject(:region) { described_class::NTSC_OLD }

    it "clocks the 6567R56A's 64 cycles by 262 lines at 1,022,727 Hz" do
      expect([region.clock_hz, region.cycles_per_line, region.lines_per_frame]).to eq([1_022_727, 64, 262])
    end

    it "fetches sprite 0 in cycle 59 and turns its display on in cycle 58" do
      expect([region.sprite_cycle, region.sprite_display_cycle]).to eq([59, 58])
    end

    it "runs the X counter straight through" do
      expect(region.x_hold).to eq(0)
    end
  end
end
