# frozen_string_literal: true

require "spec_helper"

describe Badline::PET::DiscreteVideo do
  subject(:video) { described_class.new(cells, characters, via) }

  let(:cells) { Array.new(0x400, 0x20) }
  let(:characters) { Badline::PET::Characters.new("pet/characters2.rom") }
  let(:via) { instance_double(Badline::PET::VIA, ca2_output: false) }
  let(:canvas) { video.canvas }

  # The eight dots from `column` of `line`, as a byte, leftmost in bit 7.
  def dots(column, line) = canvas.display[(line * canvas.width) + column, 8].reduce(0) { |bits, dot| (bits << 1) | dot }

  def run(cycles) = cycles.times { video.cycle! }

  # 'A' in the graphics set, and 'a' in the text set.
  def a_row(row, set: 0) = characters.rows[set | (1 << 3) | row]

  # Pinned by PET/hi-res: its picture matches hi-res.bitmap with the
  # characters 6 to 32 cycles after the vertical drive line rose.
  it "shows a line's characters in its last 40 cycles" do
    cells[0] = 1
    run(25)
    expect(dots(32, 8)).to eq(a_row(0))
  end

  it "reads the screen RAM in the cycle it shows the character" do
    run(24)
    cells[0] = 1
    run(1)
    expect(dots(32, 8)).to eq(a_row(0))
  end

  it "shows a write after that cycle from the next line" do
    run(25)
    cells[0] = 1
    run(64)
    expect([dots(32, 8), dots(32, 9)]).to eq([0, a_row(1)])
  end

  it "shows the text set while VIA CA2 is high" do
    allow(via).to receive(:ca2_output).and_return(true)
    cells[0] = 1
    run(25)
    expect(dots(32, 8)).to eq(a_row(0, set: Badline::PET::Characters::TEXT))
  end

  it "inverts a screen code with bit 7 set" do
    cells[1] = 0x81
    run(26)
    expect(dots(40, 8)).to eq(a_row(0) ^ 0xff)
  end

  it "steps a character row every 8 lines" do
    cells[40] = 1
    run((8 * 64) + 25)
    expect(dots(32, 16)).to eq(a_row(0))
  end

  # Pinned by xpet's 2001 and 3032: 16,640 cycles from one fall of the
  # line to the next, 3,840 of them low.
  it "drops the vertical drive line right after line 199's last character" do
    run(200 * 64)
    expect(video.vertical_drive?).to be(false)
  end

  it "keeps it high until then" do
    run((200 * 64) - 1)
    expect(video.vertical_drive?).to be(true)
  end

  it "raises it again 60 lines later" do
    run(260 * 64)
    expect([video.vertical_drive?, video.line, video.column]).to eq([true, 0, 0])
  end
end
