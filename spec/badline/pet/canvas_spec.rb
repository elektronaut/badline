# frozen_string_literal: true

require "spec_helper"

describe Badline::PET::Canvas do
  subject(:canvas) { described_class.new(64, 4) }

  def dots(column, line, count = 8) = canvas.display[(line * canvas.width) + column, count]

  it "paints a row of dots, leftmost from bit 7" do
    canvas.paint(8, 1, 0b1000_0001)
    expect(dots(8, 1)).to eq([1, 0, 0, 0, 0, 0, 0, 1])
  end

  it "marks the line it paints" do
    canvas.clear_dirty_lines!
    canvas.paint(8, 1, 0xff)
    expect(canvas.dirty_lines).to eq([false, true, false, false])
  end

  it "leaves a line alone when the same row paints it again" do
    canvas.paint(8, 1, 0xff)
    canvas.clear_dirty_lines!
    canvas.paint(8, 1, 0xff)
    expect(canvas.dirty_lines).to all(be(false))
  end

  it "paints over dots another painting overlapped" do
    canvas.paint(8, 1, 0xff)
    canvas.paint(12, 1, 0x00)
    canvas.paint(8, 1, 0xff)
    expect(dots(8, 1)).to all(eq(1))
  end

  it "leaves out a row that runs past the edge" do
    canvas.paint(60, 1, 0xff)
    expect(canvas.display).to all(eq(0))
  end

  def paint_span(line, columns)
    columns.each { |column| canvas.paint(column, line, 0xff) }
    canvas.span(line, columns.min, columns.max + 8)
  end

  it "blacks out what a line's last span covered beyond its new one" do
    paint_span(2, [0, 8, 16])
    paint_span(2, [8])
    expect(dots(0, 2, 24)).to eq(([0] * 8) + ([1] * 8) + ([0] * 8))
  end

  it "shows black and the phosphor's green" do
    expect(canvas.palette).to eq([0x000000, 0x41ff00])
  end
end
