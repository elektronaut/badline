# frozen_string_literal: true

require "spec_helper"
require "badline/cbm2"

describe Badline::CBM2::Bus do
  subject(:bus) { described_class.new(basic: "cbm2/basic128.rom", kernal: "cbm2/kernal-04a.rom", ram_segments: [1, 2]) }

  # What a read of +addr+ finds just after the bus carried +last+.
  def read_after(last, addr)
    bus.poke(0x0002, last)
    bus.peek(addr)
  end

  it "starts in segment 15 for both registers" do
    expect([bus.execution_segment, bus.indirect_segment]).to eq([15, 15])
  end

  it "reads the registers at $0000 and $0001, the high four bits 0" do
    bus.poke(0x0001, 0xf2)
    expect([bus.peek(0x0000), bus.peek(0x0001)]).to eq([0x0f, 0x02])
  end

  it "reads the KERNAL at $E000-$FFFF and BASIC at $8000-$BFFF of segment 15" do
    expect([bus.peek(0xe000), bus.peek(0x8000)])
      .to eq([Badline::ROM.read("cbm2/kernal-04a.rom").first, Badline::ROM.read("cbm2/basic128.rom").first])
  end

  it "keeps the system RAM at $0002-$07FF and the screen RAM at $D000-$D7FF" do
    bus.poke(0x07ff, 0x12)
    bus.poke(0xd7ff, 0x34)
    expect([bus.peek(0x07ff), bus.peek(0xd7ff)]).to eq([0x12, 0x34])
  end

  it "reads the last byte on the bus from the empty slots of segment 15" do
    expect([read_after(0x42, 0x0800), read_after(0x43, 0x2000), read_after(0x44, 0xc000)]).to eq([0x42, 0x43, 0x44])
  end

  it "lets writes to ROM go nowhere" do
    bus.poke(0xe000, 0x00)
    expect(bus.peek(0xe000)).to eq(Badline::ROM.read("cbm2/kernal-04a.rom").first)
  end

  it "switches the CPU's accesses to the segment written to $0000" do
    bus.poke(0x0000, 0x01)
    bus.poke(0x0234, 0x56)
    expect([bus.peek_bank(1, 0x0234), bus.peek_bank(15, 0x0234)]).to eq([0x56, 0x00])
  end

  it "answers the registers in every segment" do
    bus.poke(0x0000, 0x02)
    bus.poke(0x0001, 0x01)
    expect([bus.peek(0x0000), bus.peek(0x0001)]).to eq([0x02, 0x01])
  end

  it "reads the last byte on the bus from a segment the RAM board leaves empty" do
    bus.poke(0x0000, 0x05)
    expect(read_after(0x77, 0x4000)).to eq(0x77)
  end

  it "reads and writes the indirection segment while it is selected" do
    bus.poke(0x0001, 0x02)
    bus.select_indirect!
    bus.poke(0x0300, 0x99)
    bus.select_execute!
    expect([bus.peek_bank(2, 0x0300), bus.peek(0x0300)]).to eq([0x99, 0x00])
  end

  it "maps an I/O chip into its page of segment 15" do
    chip = Badline::Memory.new([], length: 0x100, start: 0xdc00)
    bus.map_io(0xdc, chip)
    bus.poke(0xdc05, 0x21)
    expect(chip.peek(0xdc05)).to eq(0x21)
  end

  it "reads a cartridge's ROM at its load address in segment 15" do
    chip = Badline::Storage::CRTFile::Chip.new(chip_type: 0, bank: 0, address: 0x2000, data: [0x4c] * 0x2000)
    bus.attach_cartridge([chip])
    expect([bus.peek(0x2000), bus.peek(0x3fff), read_after(0x11, 0x4000)]).to eq([0x4c, 0x4c, 0x11])
  end

  it "calls the debug register's handler with a write to $DAFF in segment 15" do
    codes = []
    bus.install_debug_register { |code| codes << code }
    bus.poke(0xdaff, 0xff)
    expect(codes).to eq([0xff])
  end

  it "says the KERNAL is mapped only while the CPU executes in segment 15" do
    bus.poke(0x0000, 0x01)
    expect(bus.kernal_mapped?).to be(false)
  end
end
