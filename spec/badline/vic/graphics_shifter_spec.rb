# frozen_string_literal: true

require "spec_helper"

# The shift register pixel by pixel, for the groups where the mode or the
# load point changes. Pinned by split-tests/modesplit, which switches every
# mode mid-line under all eight XSCROLL values.
RSpec.describe Badline::VIC::GraphicsShifter do
  subject(:shifter) { described_class.new(registers) }

  let(:registers) { Badline::VIC::Registers.new }

  # Mode bits as the sequencer numbers them: ECM 4, BMM 2, MCM 1.
  def group(from:, to:, data: 0, screencode: 0x40, color: 1)
    shifter.prime(0, screencode, color, 0, from)
    shifter.draw(data, screencode, color, 0, to)
    shifter.colors
  end

  before do
    registers.write(0x21, 6)
    registers.write(0x22, 5)
    registers.write(0x23, 4)
  end

  it "takes a rising ECM at pixel 4" do
    expect(group(from: 0, to: 4)).to eq([6, 6, 6, 6, 5, 5, 5, 5])
  end

  it "shows the invalid mode while a rising BMM overlaps a falling ECM" do
    expect(group(from: 4, to: 2, screencode: 0x47)).to eq([5, 5, 5, 5, 0, 0, 7, 7])
  end

  it "takes a falling ECM at pixel 6" do
    expect(group(from: 4, to: 0)).to eq([5, 5, 5, 5, 5, 5, 6, 6])
  end

  # The lookup switches to multicolour at pixel 4, but the register is read
  # as hi-res until pixel 7, where the multicolour flip-flop resets and the
  # pixel holds.
  it "reads a rising MCM from pixel 7" do
    expect(group(from: 0, to: 1, data: 0b0101_0101, color: 0x0a))
      .to eq([6, 0x0a, 6, 0x0a, 6, 4, 6, 6])
  end

  # Pinned by videomode1 and videomode-z: out of the invalid ECM+MCM mode,
  # pixel 4 is still black and the pairs are read through pixel 7.
  it "takes an MCM falling out of ECM+MCM a pixel late" do
    expect(group(from: 5, to: 4, data: 0b0110_0110, screencode: 0, color: 0x0e))
      .to eq([0, 0, 0, 0, 0, 6, 0x0e, 0x0e])
  end

  it "reads hi-res again from the next group" do
    group(from: 5, to: 4, screencode: 0, color: 0x0e)
    shifter.draw(0b1000_0000, 0, 0x0e, 0, 4)
    expect(shifter.colors.first(2)).to eq([0x0e, 6])
  end

  it "shows zero data ahead of a byte whose load point moved right" do
    shifter.prime(0xff, 0, 1, 0, 0)
    shifter.draw(0xff, 0, 1, 3, 0)
    expect(shifter.colors).to eq([6, 6, 6, 1, 1, 1, 1, 1])
  end

  it "marks the high bit of each pixel as foreground" do
    group(from: 0, to: 0, data: 0b1000_0001, screencode: 0)
    expect(shifter.fg).to eq([true, false, false, false, false, false, false, true])
  end
end
