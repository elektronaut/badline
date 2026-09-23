# frozen_string_literal: true

require "spec_helper"
require_relative "../../support/cartridge_builder"

describe Badline::Cartridge::SuperGames do
  include CartridgeBuilder

  let(:basic) { 0x94 }
  let(:chips) { [chip16k(bank: 0, fill: 0x10), chip16k(bank: 1, fill: 0x20)] }
  let(:bus) { attached_bus(build_cartridge(8, chips, game: 0)) }

  it "boots with bank 0 in 16K mode" do
    expect(bus[0xa000]).to eq(0x11)
  end

  it "selects a 16K bank on an I/O 2 write" do
    bus[0xdf00] = 0x01
    expect(bus[0xa000]).to eq(0x21)
  end

  it "ignores I/O 1 writes" do
    bus[0xde00] = 0x01
    expect(bus[0x8000]).to eq(0x10)
  end

  it "switches the ROM out with bit 2" do
    bus[0xdf00] = 0x04
    expect(bus[0xa000]).to eq(basic)
  end

  it "locks the register with bit 3" do
    bus[0xdf00] = 0x08
    bus[0xdf00] = 0x01
    expect(bus[0x8000]).to eq(0x10)
  end
end
