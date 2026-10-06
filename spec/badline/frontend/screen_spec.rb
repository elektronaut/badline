# frozen_string_literal: true

require "spec_helper"
require "badline/ffi"
require "badline/frontend"

describe Badline::Frontend::Screen do
  def screen(machine) = described_class.new(machine.video, machine.timing.crop)

  def size(machine) = screen(machine).then { |built| [built.width, built.height, built.row_bytes] }

  it "is PAL's crop on a PAL C64" do
    expect(size(Badline::Computer.new)).to eq([384, 272, 384 * 4])
  end

  it "keeps PAL's height for an NTSC C64" do
    expect(size(Badline::Computer.new(region: Badline::Region::NTSC))).to eq([384, 272, 384 * 4])
  end

  it "is the VIC-20's 284 by 284 crop" do
    expect(size(Badline::Vic20.new)).to eq([284, 284, 284 * 4])
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
