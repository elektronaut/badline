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

  # The 6567R8's counter reads $184-$187 three times over, so a sprite
  # there can start again.
  it "reads $184 three times on the 6567R8" do
    expect(pixels(Badline::Region::NTSC)[0x184]).to eq([492, 496, 500])
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
