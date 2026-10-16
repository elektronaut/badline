# frozen_string_literal: true

require "spec_helper"
require_relative "../../support/crtc_recorder"

describe Badline::Chips::CRTC do
  subject(:crtc) { described_class.new(output) }

  let(:output) { CRTCRecorder.new }

  # A small frame: lines of 10 characters, 4 shown, sync at 6; rows of 2
  # lines, 4 rows, 2 shown, sync at row 3; the screen from $1000.
  let(:small) { [9, 4, 6, 0x0f, 3, 0, 2, 3, 0, 1, 0, 0, 0x10, 0x00] }

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
    before do
      program(text_mode)
      crtc.reset!
    end

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
    crtc.reset!
    expect(sync_period.last).to eq(50 * ((33 * 10) + 3))
  end

  it "starts over at the top of the frame after a reset" do
    program(text_mode)
    1234.times { crtc.cycle! }
    crtc.reset!
    expect([crtc.row, crtc.line, crtc.column, crtc.vsync?]).to eq([0, 0, 0, false])
  end

  describe "counting a small frame" do
    before do
      program(small)
      crtc.reset!
      output.clear
    end

    def run(cycles) = cycles.times { crtc.cycle! }

    def addresses = output.characters.map(&:first)

    def write_and_run(register, value, cycles)
      write(register, value)
      run(cycles)
    end

    it "shows R1 characters a line from the start address" do
      run(10)
      expect(addresses).to eq([0x1000, 0x1001, 0x1002, 0x1003])
    end

    it "starts each line of a row again from the row's start" do
      run(20)
      expect(output.characters.last(4).map { |address, raster, _| [address, raster] })
        .to eq([[0x1000, 1], [0x1001, 1], [0x1002, 1], [0x1003, 1]])
    end

    it "moves the next row's start to where the row's last line met R1" do
      run(30)
      expect(addresses.last(4)).to eq([0x1004, 0x1005, 0x1006, 0x1007])
    end

    it "counts the characters since horizontal sync started at R2" do
      run(20)
      expect(output.characters[4].last).to eq(4)
    end

    it "hears of a horizontal sync each line" do
      run(30)
      expect(output.hsyncs).to eq(3)
    end

    it "stops the display at the start of row R6, and says so" do
      run(80)
      expect([output.characters.length, output.rows_ends]).to eq([16, 1])
    end

    it "starts the next frame from the start address again" do
      run(81)
      expect([addresses.last, output.frame_starts]).to eq([0x1000, 1])
    end

    # Pinned by CRTC/crtc6 and crtc7: R1 written after the counter passed
    # it leaves the display on to the line's end, with MA counting on.
    it "runs the display to the line's end past an R1 it missed" do
      run(3)
      write(1, 2)
      run(7)
      expect(addresses).to eq((0x1000..0x1009).to_a)
    end

    # Pinned by CRTC/crtc6: a row whose last line missed R1 doesn't move
    # the next row's start, so the row repeats.
    it "repeats a row whose last line missed R1" do
      run(13)
      write(1, 2)
      run(7)
      write_and_run(1, 4, 10)
      expect(addresses.last(4)).to eq([0x1000, 0x1001, 0x1002, 0x1003])
    end

    # Pinned by CRTC/crtc10: R9 lowered below the line counter stretches
    # the row to 32 lines.
    it "runs a row on to 32 lines past an R9 it missed" do
      run(12)
      write(9, 0)
      run(303)
      expect(output.characters.last.take(2)).to eq([0x1003, 31])
    end

    # Pinned by CRTC/crtc13: R6 lowered below the row counter leaves the
    # display on to the frame's end.
    it "shows every row past an R6 it missed" do
      run(25)
      write(6, 0)
      run(54)
      expect([output.characters.length, output.rows_ends]).to eq([32, 0])
    end
  end
end
