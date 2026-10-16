# frozen_string_literal: true

require "spec_helper"
require "badline/pet"

describe Badline::Chips::CRTC do
  subject(:crtc) { described_class.new }

  # The 8032's 50 Hz editor's text-mode table, R0-R9: 50 cycles a line,
  # 40 rows of 10 lines, vertical sync from row 32.
  let(:text_mode) { [0x31, 0x28, 0x29, 0x0f, 0x27, 0x00, 0x19, 0x20, 0x00, 0x09] }

  def program(values) = values.each_with_index { |value, register| write(register, value) }

  def write(register, value)
    crtc.poke(0xe880, register)
    crtc.poke(0xe881, value)
  end

  # The cycles from one start of vertical sync to the next, and how long
  # it lasted.
  def sync_period
    crtc.cycle! until crtc.vsync?
    length = cycles_until { !crtc.vsync? }
    [length, length + cycles_until { crtc.vsync? }]
  end

  def cycles_until
    count = 0
    until yield && count.positive?
      crtc.cycle!
      count += 1
    end
    count
  end

  it "writes the register the address register selects" do
    write(0x0c, 0x10)
    expect(crtc.registers[12]).to eq(0x10)
  end

  it "keeps the bits each register has" do
    write(0x04, 0xff)
    write(0x09, 0xff)
    expect([crtc.registers[4], crtc.registers[9]]).to eq([0x7f, 0x1f])
  end

  it "reads back the cursor and light pen registers" do
    write(0x0e, 0x12)
    expect(crtc.peek(0xe881)).to eq(0x12)
  end

  it "reads 0 from the registers it can't read back" do
    write(0x00, 0x31)
    expect([crtc.peek(0xe881), crtc.peek(0xe880)]).to eq([0, 0])
  end

  it "ignores writes past R17" do
    write(0x12, 0x55)
    expect(crtc.registers.length).to eq(18)
  end

  describe "with the 8032's 50 Hz text mode" do
    before { program(text_mode) }

    it "runs a frame of 20,000 cycles, with vertical sync for 16 lines of 50" do
      expect(sync_period).to eq([800, 20_000])
    end

    it "starts vertical sync on the first line of row 32" do
      crtc.cycle! until crtc.vsync?
      expect([crtc.row, crtc.line, crtc.column]).to eq([32, 0, 0])
    end
  end

  it "adds the vertical adjust's lines to the frame" do
    program([0x31, 0x28, 0x29, 0x0f, 0x20, 0x03, 0x19, 0x1d, 0x00, 0x09])
    expect(sync_period.last).to eq(50 * ((33 * 10) + 3))
  end

  it "starts over at the top of the frame after a reset" do
    program(text_mode)
    1234.times { crtc.cycle! }
    crtc.reset!
    expect([crtc.row, crtc.line, crtc.column, crtc.vsync?]).to eq([0, 0, 0, false])
  end
end
