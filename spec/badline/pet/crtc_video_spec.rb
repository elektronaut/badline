# frozen_string_literal: true

require "spec_helper"

describe Badline::PET::CRTCVideo do
  subject(:video) { described_class.new(characters, via, registers, columns80: true) }

  let(:characters) { Badline::PET::Characters.new("pet/characters2.rom") }
  let(:via) { instance_double(Badline::PET::VIA, ca2_output: false) }
  let(:registers) { [0x3a, 0x28, 0x2c, 0x08, 0x29, 0x03, 0x19, 0x22, 0x00, 0x07, 0, 0, 0x10, 0x00, 0, 0, 0, 0] }
  let(:cells) { Array.new(0x800, 0x20) }
  let(:canvas) { video.canvas }

  before { video.cells = cells }

  def dots(column, line) = canvas.display[(line * canvas.width) + column, 8].reduce(0) { |bits, dot| (bits << 1) | dot }

  def a_row(row) = characters.rows[(1 << 3) | row]

  # The first character of a frame's first line, as the CRTC hands it
  # over: 15 characters after the last line's horizontal sync.
  def first(address: 0x1000, raster: 0) = video.character(address, raster, 15)

  it "frames 25 rows of 8 lines from line 36 and 40 characters from dot 32, as xpet does" do
    cells[0] = 1
    first
    expect(dots(32, 36)).to eq(a_row(0))
  end

  it "shows the byte after on the right half of an 80-column character" do
    cells[1] = 1
    first
    expect(dots(40, 36)).to eq(a_row(0))
  end

  it "inverts the picture while MA12 is low" do
    cells[0] = 1
    first(address: 0x0000)
    expect(dots(32, 36)).to eq(a_row(0) ^ 0xff)
  end

  it "blanks the lines with RA3 set" do
    cells[0] = 0xa0
    first(raster: 8)
    expect(dots(32, 36)).to eq(0)
  end

  it "shows RA4's lines as the first eight" do
    cells[0] = 1
    first(raster: 17)
    expect(dots(32, 36)).to eq(a_row(1))
  end

  it "shows the text set while VIA CA2 is high" do
    allow(via).to receive(:ca2_output).and_return(true)
    cells[0] = 1
    first
    expect(dots(32, 36)).to eq(characters.rows[Badline::PET::Characters::TEXT | (1 << 3)])
  end

  it "moves a character one sync later one character right" do
    cells[0] = 1
    video.character(0x1000, 0, 16)
    expect(dots(48, 36)).to eq(a_row(0))
  end

  it "takes the next line of the picture at horizontal sync" do
    cells[0] = 1
    video.hsync
    first(raster: 1)
    expect(dots(32, 37)).to eq(a_row(1))
  end

  def show_lines(count)
    count.times do
      video.character(0x1000, 0, 15)
      video.line_end
    end
    video.rows_end
  end

  it "frames the next frame by the lines shown before the display stopped" do
    show_lines(120)
    video.frame_start
    cells[0] = 1
    first
    expect(dots(32, (273 - 121) / 2)).to eq(a_row(0))
  end
end
