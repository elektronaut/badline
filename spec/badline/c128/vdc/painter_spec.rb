# frozen_string_literal: true

require "spec_helper"

describe Badline::C128::VDC::Painter do
  subject(:painter) { described_class.new(registers, memory) }

  let(:registers) { Array.new(37, 0) }
  let(:memory) { Badline::C128::VDC::Memory.new(16) }

  # 16 characters of 8 dots a line, 4 displayed, the horizontal sync at
  # 10 for one character, on a background of colour 2. The first character
  # shows %11111111 in colour 5, without attributes.
  before do
    { 0 => 15, 1 => 4, 2 => 10, 3 => 0x11, 6 => 1, 9 => 7, 22 => 0x78, 25 => 0x07, 26 => 0x52,
      28 => 0x20 }.each { |reg, value| registers[reg] = value }
    memory.store(0x2000, 0xff)
    painter.begin_frame(128, 8)
  end

  def line(line_y = 0) = painter.display[line_y * 128, 128]

  it "is as wide as a line and as high as a frame" do
    expect([painter.width, painter.height]).to eq([128, 8])
  end

  it "caps its size" do
    painter.begin_frame(4096, 1000)
    expect([painter.width, painter.height]).to eq([1024, 320])
  end

  it "starts each line where the horizontal sync ends, 7 characters behind the counter" do
    painter.paint(0, 0, 0, false, 0)
    expect(line[95, 9]).to eq([2] + ([5] * 8))
  end

  it "paints the border in the background colour" do
    painter.paint(0, -1, 0, false, 0)
    expect(line.uniq).to eq([2])
  end

  it "paints the vertical sync black" do
    painter.paint(0, 0, 0, true, 0)
    expect(line.uniq).to eq([0])
  end

  it "blanks the characters outside R34 up to R35" do
    registers[34] = 2
    registers[35] = 4
    painter.paint(0, -1, 0, false, 0)
    expect([line[55], line[56], line[71], line[72]]).to eq([0, 2, 2, 0])
  end

  it "marks the lines it paints dirty" do
    painter.clear_dirty_lines!
    painter.paint(3, 0, 0, false, 0)
    expect(painter.dirty_lines.each_index.select { |n| painter.dirty_lines[n] }).to eq([3])
  end

  it "crops a line's horizontal sync and a frame's vertical sync" do
    expect(painter.crop(128, 8, 2)).to eq([0, 0, 120, 6])
  end
end
