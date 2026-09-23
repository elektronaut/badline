# frozen_string_literal: true

require "spec_helper"
require_relative "../../support/cartridge_builder"

describe Badline::Cartridge::Mach5 do
  include CartridgeBuilder

  let(:rom) { Array.new(0x2000) { |i| (i >> 8) + 1 } }
  let(:crt_chip) { Badline::Storage::CRTFile::Chip.new(chip_type: 0, bank: 0, address: 0x8000, data: rom) }
  let(:bus) { attached_bus(build_cartridge(51, [crt_chip])) }

  it "reads the ROM's second-to-last page in I/O 1" do
    expect(bus[0xde00]).to eq(0x1f)
  end

  it "reads the ROM's last page in I/O 2" do
    expect(bus[0xdf00]).to eq(0x20)
  end

  it "switches the ROM out on an I/O 2 write" do
    bus[0xdf00] = 0
    expect(bus[0x8000]).to eq(0x00)
  end

  it "switches the ROM in on an I/O 1 write" do
    bus[0xdf00] = 0
    bus[0xde00] = 0
    expect(bus[0x8000]).to eq(0x01)
  end
end
