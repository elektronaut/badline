# frozen_string_literal: true

require "spec_helper"
require "badline/cbm2"

describe Badline::CBM2::CRTCVideo do
  subject(:video) { described_class.new(glyphs, screen, tpi, registers, high_profile: false) }

  # Glyph g's row r holds g + r, so a painted row names its glyph.
  let(:glyphs) { Array.new(4096) { |index| ((index >> 4) + (index & 0x0f)) & 0xff } }
  let(:screen) { Badline::Memory.new([], length: 0x800, start: 0xd000) }
  let(:tpi) { Struct.new(:ca?).new(false) }
  # The 600's 50 Hz table: lines of 128 characters, sync at 96.
  let(:registers) do
    Array.new(18, 0).tap do |regs|
      regs[0] = 0x7f
      regs[1] = 80
      regs[2] = 0x60
      regs[10] = 0x20
    end
  end

  # The dots painted at the first row's line +raster+, character +column+.
  def dots(raster, column = 0)
    canvas = video.canvas
    start = ((33 + raster) * canvas.width) + 32 + (column * 8)
    canvas.display[start, 8].each_with_index.sum { |dot, index| dot << (7 - index) }
  end

  # The CRTC displaying character +column+ of the first row at +raster+.
  def display(column, raster) = video.character(column, raster, 32 + column)

  it "paints the glyph's row from the screen code at the first row's line, 32 dots in" do
    screen.poke(0xd001, 0x05)
    display(1, 0)
    expect(dots(0, 1)).to eq(0x05)
  end

  it "reads the glyph's row from the raster line" do
    screen.poke(0xd000, 0x05)
    video.line_end
    video.line_end
    display(0, 2)
    expect(dots(0)).to eq(0x07)
  end

  it "reverses a screen code with bit 7 set" do
    screen.poke(0xd000, 0x85)
    display(0, 0)
    expect(dots(0)).to eq(0x05 ^ 0xff)
  end

  it "takes the second set's glyphs while TPI1's CA is high" do
    tpi[:ca?] = true
    screen.poke(0xd000, 0x05)
    display(0, 0)
    expect(dots(0)).to eq(0x85)
  end

  describe "the cursor" do
    before do
      registers[14] = 0x00
      registers[15] = 0x00
      registers[11] = 7
    end

    it "reverses the character at R14:R15 from line R10 to R11 when steady" do
      registers[10] = 0x02
      display(0, 1)
      video.line_end
      display(0, 2)
      expect([dots(0), dots(1)]).to eq([0x01, 0x02 ^ 0xff])
    end

    it "shows nowhere in R10's mode 01" do
      registers[10] = 0x20
      display(0, 0)
      expect(dots(0)).to eq(0x00)
    end

    # The cursor's dots in the next field.
    def field
      video.frame_start
      display(0, 0)
      dots(0)
    end

    def fields = Array.new(16) { field }

    it "blinks on for 8 fields and off for 8 in mode 10" do
      registers[10] = 0x40
      expect(fields.count(0xff)).to eq(8)
    end
  end

  it "blacks the picture out when the frame's layout changes" do
    screen.poke(0xd000, 0x05)
    display(0, 0)
    registers[1] = 40
    video.frame_start
    expect(dots(0)).to eq(0)
  end
end
