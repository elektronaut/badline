# frozen_string_literal: true

require "spec_helper"

describe Badline::C128::VDC::Window do
  subject(:window) { described_class.new(registers, memory) }

  let(:registers) { Array.new(37, 0) }
  let(:memory) { Badline::C128::VDC::Memory.new(16) }

  # Two characters of 8 pixels, 8 lines, with attributes: the screen at
  # $0000, attributes at $0800, the character set at $2000, the cursor off.
  # Character 1's top line is %10100000, in colour 5 on black.
  before do
    { 1 => 2, 9 => 7, 10 => 0x20, 20 => 0x08, 22 => 0x78, 23 => 8, 25 => 0x47, 26 => 0xf0, 28 => 0x20,
      29 => 7 }.each { |reg, value| registers[reg] = value }
    memory.store(0x0000, 1)
    memory.store(0x0800, 0x05)
    memory.store(0x2010, 0b1010_0000)
  end

  def paint(row_line: 0, frame: 0, row: 0)
    window.latch_starts
    line = Array.new(32, 9)
    window.paint(line, row, row_line, frame)
    line
  end

  def first_cell(**) = paint(**)[0, 8]

  describe "text mode" do
    it "paints the pattern in the attribute's colour on the background" do
      expect(first_cell).to eq([5, 0, 5, 0, 0, 0, 0, 0])
    end

    it "paints R26's foreground without attributes" do
      registers[25] = 0x07
      expect(first_cell).to eq([15, 0, 15, 0, 0, 0, 0, 0])
    end

    it "reverses a character with attribute bit 6" do
      memory.store(0x0800, 0x45)
      expect(first_cell).to eq([0, 5, 0, 5, 5, 5, 5, 5])
    end

    it "takes the second set with attribute bit 7" do
      memory.store(0x0800, 0x85)
      memory.store(0x3010, 0b0000_0001)
      expect(first_cell).to eq([0, 0, 0, 0, 0, 0, 0, 5])
    end

    it "underlines R29's line with attribute bit 5" do
      memory.store(0x0800, 0x25)
      expect(first_cell(row_line: 7)).to eq([5] * 8)
    end

    it "reverses everything with R24 bit 6" do
      registers[24] = 0x40
      expect(first_cell).to eq([0, 5, 0, 5, 5, 5, 5, 5])
    end

    it "reads 32 bytes a character from R28 bits 6-7 with R9 past 15" do
      registers[9] = 16
      memory.store(0x0020, 0b1100_0000)
      expect(first_cell).to eq([5, 5, 0, 0, 0, 0, 0, 0])
    end

    it "paints the lines past R23 in the background" do
      registers[23] = 3
      memory.store(0x2014, 0xff)
      expect(first_cell(row_line: 4)).to eq([0] * 8)
    end

    it "scrolls up by R24 bits 0-4 lines" do
      registers[24] = 2
      memory.store(0x2012, 0xff)
      expect(first_cell).to eq([5] * 8)
    end

    it "steps rows by R1 + R27" do
      registers[27] = 3
      memory.store(0x0005, 1)
      memory.store(0x0805, 0x02)
      expect(first_cell(row: 1)).to eq([2, 0, 2, 0, 0, 0, 0, 0])
    end
  end

  describe "the character's width" do
    it "scrolls left by R22's width less one less R25 bits 0-3" do
      registers[25] = 0x46
      expect(first_cell).to eq([0, 5, 0, 0, 0, 0, 0, 0])
    end

    it "displays up to R22 bits 0-3's pixel" do
      registers[22] = 0x71
      memory.store(0x2010, 0xff)
      expect(first_cell).to eq([5, 5, 0, 0, 0, 0, 0, 0])
    end

    it "repeats the last displayed pixel in the semigraphic mode" do
      registers[22] = 0x72
      registers[25] = 0x67
      expect(first_cell).to eq([5, 0, 5, 5, 5, 5, 5, 5])
    end

    it "doubles each pixel in the double-width mode" do
      registers[22] = 0x89
      registers[25] = 0x57
      expect(first_cell).to eq([5, 5, 0, 0, 5, 5, 0, 0])
    end
  end

  describe "blinking" do
    before { memory.store(0x0800, 0x15) }

    it "shows the character for the first 8 of 16 frames" do
      expect(first_cell(frame: 7)).to eq([5, 0, 5, 0, 0, 0, 0, 0])
    end

    it "hides it for the other 8" do
      expect(first_cell(frame: 8)).to eq([0] * 8)
    end

    it "blinks at 1/32 of the frame rate with R24 bit 5" do
      registers[24] = 0x20
      expect(first_cell(frame: 8)).to eq([5, 0, 5, 0, 0, 0, 0, 0])
    end
  end

  describe "the cursor" do
    before do
      registers[10] = 0x00
      registers[11] = 8
    end

    it "reverses its character, solid in mode 0" do
      expect(first_cell(frame: 8)).to eq([0, 5, 0, 5, 5, 5, 5, 5])
    end

    it "is hidden in mode 1" do
      registers[10] = 0x20
      expect(first_cell).to eq([5, 0, 5, 0, 0, 0, 0, 0])
    end

    it "blinks at 1/16 of the frame rate in mode 2" do
      registers[10] = 0x40
      expect([first_cell(frame: 7)[1], first_cell(frame: 8)[1]]).to eq([5, 0])
    end

    it "blinks at 1/32 of the frame rate in mode 3" do
      registers[10] = 0x60
      expect([first_cell(frame: 15)[1], first_cell(frame: 16)[1]]).to eq([5, 0])
    end

    it "covers the lines from R10 wrapping round to before R11" do
      registers[10] = 6
      registers[11] = 2
      expect([1, 2, 6].map { |line| first_cell(row_line: line)[7] }).to eq([5, 0, 5])
    end

    it "stays off characters elsewhere" do
      registers[15] = 1
      expect(first_cell).to eq([5, 0, 5, 0, 0, 0, 0, 0])
    end
  end

  describe "bitmap mode" do
    before do
      registers[25] = 0x87
      registers[26] = 0xe2
      memory.store(0x0000, 0b1000_0001)
      memory.store(0x0002, 0b0100_0000)
    end

    it "paints the bytes in R26's colours" do
      expect(first_cell).to eq([14, 2, 2, 2, 2, 2, 2, 14])
    end

    it "reads each scan line R1 + R27 bytes on" do
      expect(first_cell(row_line: 1)).to eq([2, 14, 2, 2, 2, 2, 2, 2])
    end

    it "takes the foreground from attribute bits 0-3 and the background from bits 4-7" do
      registers[25] = 0xc7
      memory.store(0x0800, 0x3c)
      expect(first_cell).to eq([12, 3, 3, 3, 3, 3, 3, 12])
    end
  end
end
