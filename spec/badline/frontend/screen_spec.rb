# frozen_string_literal: true

require "spec_helper"
require "badline/ffi"
require "badline/frontend"

describe Badline::Frontend::Screen do
  def screen(machine)
    timing = machine.timing
    described_class.new(machine.video, timing.crop, pixel_width: timing.pixel_width,
                                                    frame_lines: timing.lines_per_frame)
  end

  def size(machine) = screen(machine).then { |built| [built.width, built.height, built.row_bytes] }

  # A display 300 pixels wide in the VIC-II's palette, every pixel
  # colour 1, with its 21 lines all changed.
  def fine_raster
    instance_double(Badline::Chips::VIC, width: 300, palette: Badline::Chips::VIC::PALETTE,
                                         display: Array.new(300 * 21, 1),
                                         dirty_lines: Array.new(21, true), clear_dirty_lines!: nil)
  end

  it "is PAL's crop on a PAL C64" do
    expect(size(Badline::C64.new)).to eq([384, 272, 384 * 4])
  end

  it "keeps PAL's height for an NTSC C64" do
    expect(size(Badline::C64.new(region: Badline::Region::NTSC))).to eq([384, 272, 384 * 4])
  end

  it "is the VIC-20's 284 by 284 crop" do
    expect(size(Badline::Vic20.new)).to eq([284, 284, 284 * 4])
  end

  it "is as many window pixels wide as the VIC-20's pixels are wide" do
    expect(described_class.new(Badline::Vic20.new.video, [0, 28, 284, 284], pixel_width: 2).window_width).to eq(568)
  end

  # A TED's display 4 pixels wide and 4 lines high, line N in the
  # palette index N * 0x11, with every line changed.
  def ted_raster
    instance_double(Badline::Chips::TED, width: 4, palette: Badline::Chips::TED::PALETTE,
                                         display: Array.new(16) { |pixel| (pixel / 4) * 0x11 },
                                         dirty_lines: Array.new(4, true), clear_dirty_lines!: nil)
  end

  it "is xplus4's 384 by 288 view on a PAL Plus/4" do
    expect(size(Badline::Plus4.new)).to eq([384, 288, 384 * 4])
  end

  it "keeps PAL's C64 height for an NTSC Plus/4" do
    expect(size(Badline::Plus4.new(model: "plus4ntsc"))).to eq([384, 272, 384 * 4])
  end

  describe "a crop past the frame's last line" do
    subject(:built) { described_class.new(ted_raster, [0, 2, 4, 4], frame_lines: 4) }

    it "runs on from the frame's first line, in the TED's 128 colours" do
      rows = Array.new(4) { |row| built.pixels[((row + 134) * 192) + 95] }
      expect(rows).to eq([0x22, 0x33, 0x00, 0x11].map { |index| Badline::Chips::TED::PALETTE[index] * 0x1_0000_0001 })
    end
  end

  describe "a raster of two dots to a window pixel" do
    subject(:built) { described_class.new(fine_raster, [0, 0, 201, 21], dots: 2) }

    it "is at least the C64's crop wide in window pixels, and PAL's height" do
      expect([built.width, built.window_width, built.height]).to eq([768, 384, 272])
    end

    it "centres the crop's even number of pixels" do
      built.update
      pair = Badline::Chips::VIC::PALETTE[1] * 0x1_0000_0001
      expect(built.pixels[(125 * 384) + 141, 102]).to eq([0] + ([pair] * 100) + [0])
    end

    it "starts with what the chip drew before it was built, without an update" do
      pair = Badline::Chips::VIC::PALETTE[1] * 0x1_0000_0001
      expect(built.pixels[(125 * 384) + 142, 100]).to eq([pair] * 100)
    end
  end

  describe "a VIC-20 frame" do
    let(:machine) { Badline::Vic20.new.tap { |vic20| vic20.run_cycles(2 * 71 * 312) } }
    let(:palette) { machine.video.palette }

    it "packs two pixels a word, the left one low, from line 28" do
      built = screen(machine).tap(&:update)
      left, right = machine.video.display[(100 * 284) + 120, 2]
      expect(built.pixels[((100 - 28) * 142) + 60]).to eq(palette[left] | (palette[right] << 32))
    end
  end
end
