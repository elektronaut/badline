# frozen_string_literal: true

require "spec_helper"

describe Badline::Cartridge::GeoRAM do
  let(:size) { 512 }
  let(:bus) { Badline::AddressBus.new.tap { |bus| bus.attach_cartridge(described_class.new(size:)) } }

  def select(block, page)
    bus[0xdfff] = block
    bus[0xdffe] = page
  end

  it "reads and writes RAM through the $DE00 window" do
    bus[0xde42] = 0x99
    expect(bus[0xde42]).to eq(0x99)
  end

  it "starts with the RAM cleared" do
    expect(bus[0xde00]).to eq(0x00)
  end

  it "shows the page the registers select" do
    select(3, 5)
    bus[0xde10] = 0x55
    select(3, 5)
    expect(bus[0xde10]).to eq(0x55)
  end

  it "keeps each page apart" do
    select(3, 5)
    bus[0xde10] = 0x55
    select(3, 4)
    expect(bus[0xde10]).to eq(0x00)
  end

  it "decodes 64 pages to a block" do
    select(1, 0)
    bus[0xde00] = 0x11
    select(1, 0x40)
    expect(bus[0xde00]).to eq(0x11)
  end

  it "wraps the block number at the size of the RAM" do
    select(1, 0)
    bus[0xde00] = 0x22
    select(33, 0)
    expect(bus[0xde00]).to eq(0x22)
  end

  it "takes the registers anywhere from $DF80, odd for the block" do
    bus[0xdf81] = 2
    bus[0xdf80] = 7
    bus[0xde00] = 0x33
    select(2, 7)
    expect(bus[0xde00]).to eq(0x33)
  end

  it "ignores writes below $DF80" do
    bus[0xde00] = 0x44
    bus[0xdf7f] = 1
    expect(bus[0xde00]).to eq(0x44)
  end

  it "leaves the registers write-only, reading open bus" do
    select(1, 1)
    expect(bus[0xdfff]).to eq(bus[0xdf00])
  end

  it "selects the first page on reset" do
    bus[0xde00] = 0x66
    select(4, 4)
    bus.cartridge.reset
    expect(bus[0xde00]).to eq(0x66)
  end

  it "leaves the ROM and I/O maps alone" do
    expect([bus.cartridge.exrom, bus.cartridge.game]).to eq([1, 1])
  end

  context "with 64K" do
    let(:size) { 64 }

    it "has four blocks" do
      select(0, 0)
      bus[0xde00] = 0x77
      select(4, 0)
      expect(bus[0xde00]).to eq(0x77)
    end
  end

  it "refuses a size GEO-RAM does not come in" do
    expect { described_class.new(size: 100) }.to raise_error(ArgumentError)
  end
end
