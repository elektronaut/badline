# frozen_string_literal: true

require "spec_helper"
require "badline/vic20"

describe Badline::Vic20::VIC do
  let(:machine) { Badline::Vic20.new }
  let(:vic) { machine.vic }
  let(:frame) { 71 * 312 }

  # The KERNAL's PAL screen, with the character generator moved to RAM at
  # $1000: 22 columns by 23 rows from (48, 76), a white background and a
  # cyan border, with every character blank.
  def set_up_screen(registers = {})
    machine.ram.write(0x1000, Array.new(0x1000, 0))
    { 0x9000 => 12, 0x9001 => 38, 0x9002 => 0x96, 0x9003 => 0x2e, 0x9005 => 0xfc, 0x900f => 0x1b }
      .merge(registers).each { |addr, value| vic.poke(addr, value) }
  end

  # Character 1 in the top left corner in +color+, its first pattern row
  # +pattern+.
  def put_character(color, pattern, row: 0)
    machine.ram.poke(0x1e00, 1)
    machine.bus.color_ram.poke(0x9600, color)
    machine.ram.poke(0x1008 + row, pattern)
  end

  def run(cycles)
    cycles.times { vic.cycle! }
  end

  def run_to(line, column)
    vic.cycle! until vic.rasterline == line && vic.column == column
  end

  def pixels(left, line, count = 8)
    vic.display[(line * vic.width) + left, count]
  end

  describe "the text window" do
    before do
      set_up_screen
      run(2 * frame)
    end

    it "is the background where the characters are blank" do
      expect(pixels(48, 76, 22 * 8).uniq).to eq([1])
    end

    it "ends after 22 columns" do
      expect(pixels(48 + (22 * 8), 76, 1)).to eq([3])
    end

    it "starts on the line twice the vertical origin" do
      expect(pixels(48, 75, 1)).to eq([3])
    end

    it "ends after 23 rows of 8 lines" do
      expect([pixels(48, 76 + (23 * 8) - 1, 1), pixels(48, 76 + (23 * 8), 1)]).to eq([[1], [3]])
    end

    it "leaves the border round it" do
      expect(pixels(0, 10, vic.width).uniq).to eq([3])
    end
  end

  describe "a character" do
    def draw(color, pattern, registers = {})
      set_up_screen(registers)
      put_character(color, pattern)
      run(2 * frame)
      pixels(48, 76)
    end

    it "draws its set bits in its colour and the rest in the background" do
      expect(draw(2, 0b1010_0001)).to eq([2, 1, 2, 1, 1, 1, 1, 2])
    end

    it "swaps the two while $900F bit 3 is clear" do
      expect(draw(2, 0b1010_0001, 0x900f => 0x13)).to eq([1, 2, 1, 2, 2, 2, 2, 1])
    end

    it "draws double-width background, border, colour and auxiliary pixels in multicolour" do
      expect(draw(0x0a, 0b0001_1011, 0x900e => 0x40)).to eq([1, 1, 3, 3, 2, 2, 4, 4])
    end

    it "keeps multicolour pixels as they are in reverse mode" do
      expect(draw(0x0a, 0b0001_1011, 0x900e => 0x40, 0x900f => 0x13)).to eq([1, 1, 3, 3, 2, 2, 4, 4])
    end
  end

  describe "16-line characters" do
    before do
      set_up_screen(0x9003 => 0x05)
      machine.ram.poke(0x1e00, 1)
      machine.ram.poke(0x1018, 0xff)
      run(2 * frame)
    end

    it "take their ninth line from the character's second half" do
      expect(pixels(48, 84).uniq).to eq([0])
    end

    it "make a row 16 lines high" do
      expect([pixels(48, 76 + 31, 1), pixels(48, 76 + 32, 1)]).to eq([[1], [3]])
    end
  end

  describe "the column count" do
    it "stops at 32" do
      set_up_screen(0x9000 => 1, 0x9002 => 0x80 | 40)
      run(2 * frame)
      expect([pixels(4 + 255, 76, 1), pixels(4 + 256, 76, 1)]).to eq([[1], [3]])
    end
  end

  describe "the fetches" do
    before do
      set_up_screen
      put_character(2, 0x5a)
      run(frame)
    end

    it "read the video matrix 16 cycles into the line with the origin at 12" do
      run_to(76, 16)
      expect(machine.bus.video_data).to eq(1)
    end

    it "read the character generator in the next cycle" do
      run_to(76, 17)
      expect(machine.bus.video_data).to eq(0x5a)
    end

    it "leave their byte for a read of the 3K hole" do
      run_to(76, 17)
      expect(machine.bus.peek(0x0400)).to eq(0x5a)
    end

    it "leave their byte for a read where no chip answers in I/O 0" do
      run_to(76, 17)
      expect(machine.bus.peek(0x9100)).to eq(0x5a)
    end
  end

  describe "a border colour write" do
    before do
      set_up_screen
      run(frame)
      run_to(10, 20)
      vic.poke(0x900f, 0x1d)
      run(71)
    end

    it "shows from the second pixel of the next cycle's group" do
      expect(pixels(((21 - 8) * 4) - 1, 10, 5)).to eq([3, 3, 5, 5, 5])
    end
  end

  describe "a reverse mode write over a character" do
    before do
      set_up_screen
      put_character(2, 0xff)
      run(frame)
      run_to(76, 19)
      vic.poke(0x900f, 0x63)
      run(71)
    end

    it "shows from the fourth pixel of the next cycle's group" do
      expect(pixels(48, 76)).to eq([2, 2, 2, 6, 6, 6, 6, 6])
    end
  end

  describe "#dirty_lines" do
    before do
      set_up_screen
      run(2 * frame)
      vic.clear_dirty_lines!
    end

    it "marks no line once cleared and the picture holds" do
      run(frame)
      expect(vic.dirty_lines.none?).to be(true)
    end

    it "marks the lines a change reaches" do
      vic.poke(0x900f, 0x1d)
      run(frame)
      expect(vic.dirty_lines.count(true)).to eq(312)
    end
  end

  describe "#palette" do
    it "has sixteen colours from black and white" do
      expect([vic.palette.length, vic.palette[0], vic.palette[1]]).to eq([16, 0x000000, 0xffffff])
    end
  end

  describe "#render" do
    it "leaves the display alone when off" do
      vic.render = false
      set_up_screen
      run(frame)
      expect(vic.display.uniq).to eq([0])
    end
  end
end
