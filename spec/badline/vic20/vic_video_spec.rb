# frozen_string_literal: true

require "spec_helper"
require "badline/vic20"

describe Badline::Vic20::VIC do
  let(:machine) { Badline::Vic20.new }
  let(:vic) { machine.vic }
  let(:bus) { machine.bus }

  # The KERNAL's PAL window, 22 columns by 23 rows from (12, 38), with the
  # video matrix at $1E00 and the characters in RAM at $1C00, all spaces
  # in black. White background, green border, cyan auxiliary colour.
  before do
    { 0 => 12, 1 => 38, 2 => 0x96, 3 => 0x2e, 5 => 0xff, 0x0e => 0x30, 0x0f => 0x1d }.each do |register, value|
      vic.poke(0x9000 + register, value)
    end
    506.times { |index| put(index, 0, 0) }
    8.times { |line| bus.poke(0x1c00 + line, 0) }
  end

  def run_to(line, column)
    vic.cycle! until vic.rasterline == line && vic.column == column
  end

  def frame! = ((71 * 312) + 71).times { vic.cycle! }

  def pixels(line, from, count) = vic.display[(line * vic.width) + from, count]

  def put(index, code, color)
    bus.poke(0x1e00 + index, code)
    bus.poke(0x9600 + index, color)
  end

  def character(code, bytes)
    bytes.each_with_index { |byte, line| bus.poke(0x1c00 + (code * 8) + line, byte) }
  end

  # Pinned by VIC20/split-tests/timing (dumps/dump6561e.prg).
  describe "the fetches" do
    before do
      put(0, 0x2a, 2)
      put(22, 0x2b, 2)
      character(0x2a, [0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88])
      bus.poke(0x1000, 0x5c)
    end

    it "reads the window's first code 16 cycles into its first line" do
      run_to(76, 16)
      expect(bus.video_data).to eq(0x2a)
    end

    it "reads the code's pattern byte in the cycle after" do
      run_to(78, 17)
      expect(bus.video_data).to eq(0x33)
    end

    it "reads the next row's codes from the row's ninth line" do
      run_to(84, 16)
      expect(bus.video_data).to eq(0x2b)
    end

    it "fetches nothing above the window" do
      run_to(75, 20)
      expect(bus.video_data).to eq(0x5c)
    end

    it "starts four cycles after the column in $9000" do
      vic.poke(0x9000, 5)
      run_to(76, 9)
      expect(bus.video_data).to eq(0x2a)
    end

    it "reads 16 bytes a character with $9003 bit 0 set" do
      vic.poke(0x9003, 0x2f)
      run_to(76 + 9, 17)
      expect(bus.video_data).to eq(bus.peek(0x1c00 + (0x2a * 16) + 9))
    end
  end

  describe "the picture" do
    before do
      character(1, [0xa0] * 8)
      character(2, [0x1b] * 8)
    end

    it "starts the window 48 pixels in at the KERNAL's origin" do
      put(0, 1, 2)
      frame!
      expect(pixels(76, 46, 4)).to eq([5, 5, 2, 1])
    end

    it "paints a hires character's set bits in its colour" do
      put(0, 2, 6)
      frame!
      expect(pixels(76, 48, 8)).to eq([1, 1, 1, 6, 6, 1, 6, 6])
    end

    it "swaps the colours in reverse mode" do
      put(0, 2, 6)
      vic.poke(0x900f, 0x15)
      frame!
      expect(pixels(76, 48, 8)).to eq([6, 6, 6, 1, 1, 6, 1, 1])
    end

    it "paints a multicolour character's pairs as background, border, colour and auxiliary" do
      put(0, 2, 0x0e)
      frame!
      expect(pixels(76, 48, 8)).to eq([1, 1, 5, 5, 6, 6, 3, 3])
    end

    it "ignores reverse mode for a multicolour character" do
      put(0, 2, 0x0e)
      vic.poke(0x900f, 0x15)
      frame!
      expect(pixels(76, 48, 8)).to eq([1, 1, 5, 5, 6, 6, 3, 3])
    end

    it "paints the border past the window's last column" do
      frame!
      expect(pixels(76, 222, 4)).to eq([1, 1, 5, 5])
    end

    it "paints the border below the last row" do
      frame!
      expect(pixels(76 + 184, 100, 1)).to eq([5])
    end

    it "leaves the blanked lines at the top of the frame alone" do
      frame!
      expect(pixels(27, 0, 284).uniq).to eq([0])
    end
  end

  describe "a colour write" do
    before do
      character(3, [0xff] * 8)
      put((4 * 22) + 6, 3, 8)
      frame!
      run_to(100, 30)
    end

    def written(line, register, value)
      run_to(line, 30)
      vic.poke(register, value)
      run_to(line + 1, 10)
    end

    it "changes the background from the second pixel of its cycle" do
      written(100, 0x900f, 0x2d)
      expect(pixels(100, 95, 3)).to eq([1, 1, 2])
    end

    it "changes the border from the second pixel of its cycle" do
      run_to(110, 10)
      vic.poke(0x900f, 0x1a)
      run_to(111, 10)
      expect(pixels(110, 16, 2)).to eq([5, 2])
    end

    it "turns reverse mode on two pixels later" do
      written(100, 0x900f, 0x15)
      expect(pixels(100, 95, 5)).to eq([1, 1, 1, 1, 0])
    end

    it "changes the auxiliary colour from the second pixel of its cycle" do
      written(110, 0x900e, 0x40)
      expect(pixels(110, 96, 3)).to eq([3, 4, 4])
    end
  end

  describe "#render" do
    before do
      frame!
      vic.render = false
      vic.poke(0x900f, 0x1a)
      frame!
    end

    it "leaves the display alone while off" do
      expect(pixels(76, 0, 1)).to eq([5])
    end

    it "paints every line afresh once back on" do
      vic.render = true
      frame!
      expect(pixels(76, 0, 1)).to eq([2])
    end
  end

  describe "#dirty_lines" do
    before do
      frame!
      vic.clear_dirty_lines!
    end

    it "marks only the lines that changed" do
      put(22 * 5, 1, 2)
      frame!
      expect(vic.dirty_lines.each_index.select { |line| vic.dirty_lines[line] }).to eq((116..123).to_a)
    end

    it "marks a line a colour write split" do
      run_to(200, 30)
      vic.poke(0x900f, 0x1d)
      frame!
      expect(vic.dirty_lines.each_index.select { |line| vic.dirty_lines[line] }).to eq([200])
    end
  end

  it "uses the 16 colours of the VIC-I's palette" do
    expect(vic.palette.length).to eq(16)
  end
end
