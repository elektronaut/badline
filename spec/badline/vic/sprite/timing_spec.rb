# frozen_string_literal: true

require "spec_helper"

RSpec.describe Badline::VIC::Sprite::Timing do
  def pixels(region) = described_class.new(region).x_pixels

  it "starts a sprite on PAL 104 pixels right of its X" do
    expect(pixels(Badline::Region::PAL)[0]).to eq([104])
  end

  it "never starts a sprite past X 503 on PAL" do
    expect(pixels(Badline::Region::PAL)[0x1f8]).to be_empty
  end

  it "reaches every X on the 6567R56A" do
    expect(pixels(Badline::Region::NTSC_OLD)[0x1ff]).to eq([(0x1ff + 104) % 512])
  end

  # The 6567R8's and the 6572's counter runs over $180-$187 a second time,
  # so a sprite there can start again. Pinned by spritescan_drean's 6572
  # dump: sprite 1 at $180-$186 starts past its dead pixels.
  it "reads $180 twice on the 6567R8" do
    expect(pixels(Badline::Region::NTSC)[0x180]).to eq([488, 496])
  end

  it "reads $187 twice on the 6572" do
    expect(pixels(Badline::Region::DREAN)[0x187]).to eq([495, 503])
  end

  it "reaches every X on the 6567R8, 8 pixels later past the hold" do
    expect(pixels(Badline::Region::NTSC)[0x188]).to eq([0x188 + 104 + 8])
  end

  it "puts sprite 0's BA a column later on NTSC" do
    expect(described_class.new(Badline::Region::NTSC).ba_column(0)).to eq(56)
  end

  it "moves the display compare's pixel with the 6567R8's cycle" do
    expect(described_class.new(Badline::Region::NTSC).display_off_x).to eq(468)
  end
end
