# frozen_string_literal: true

require "spec_helper"
require_relative "../../support/cartridge_builder"

describe Badline::Cartridge::EpyxFastload do
  include CartridgeBuilder

  let(:rom) { Array.new(0x2000) { |i| (i >> 8) + 1 } }
  let(:cartridge) do
    build_cartridge(10, [Badline::Storage::CRTFile::Chip.new(chip_type: 0, bank: 0, address: 0x8000, data: rom)])
  end
  let(:bus) { attached_bus(cartridge) }
  let(:now) { [1000] }

  before do
    cartridge.clock = -> { now.first }
    bus.ram.poke(0x8000, 0x5a)
  end

  it "shows the ROM for 511 cycles after reset" do
    now[0] = 1511
    expect(bus[0x8000]).to eq(0x01)
  end

  it "hides the ROM 512 cycles after reset" do
    now[0] = 1512
    expect(bus[0x8000]).to eq(0x5a)
  end

  it "holds the ROM in while ROML is read" do
    now[0] = 1400
    bus[0x8000]
    now[0] = 1900
    expect(bus[0x8000]).to eq(0x01)
  end

  it "brings the ROM back on an I/O 1 read" do
    now[0] = 3000
    bus[0xde00]
    expect(bus[0x8000]).to eq(0x01)
  end

  it "reads the ROM's last page in I/O 2" do
    now[0] = 3000
    expect(bus[0xdf00]).to eq(0x20)
  end

  it "shows the ROM again after a reset" do
    now[0] = 3000
    cartridge.reset
    expect(bus[0x8000]).to eq(0x01)
  end
end
