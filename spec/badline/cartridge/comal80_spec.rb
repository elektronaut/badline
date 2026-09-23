# frozen_string_literal: true

require "spec_helper"
require_relative "../../support/cartridge_builder"

describe Badline::Cartridge::Comal80 do
  include CartridgeBuilder

  let(:basic) { 0x94 }
  let(:chips) { [chip16k(bank: 0, fill: 0x10), chip16k(bank: 2, fill: 0x30)] }
  let(:bus) { attached_bus(build_cartridge(21, chips, game: 0, subtype:)) }
  let(:subtype) { 0 }

  it "selects a 16K bank" do
    bus[0xde00] = 0x02
    expect(bus[0xa000]).to eq(0x31)
  end

  it "switches the ROM out with bit 6" do
    bus[0xde00] = 0x40
    expect(bus[0x8000]).to eq(0x00)
  end

  it "selects the first bank in 16K mode on reset" do
    bus[0xde00] = 0x42
    bus.cartridge.reset
    expect(bus[0xa000]).to eq(0x11)
  end

  context "when it is the grey board" do
    let(:subtype) { 1 }

    it "selects 8K mode with bits 5-6" do
      bus[0xde00] = 0x40
      expect(bus[0xa000]).to eq(basic)
    end

    it "selects Ultimax mode with bits 5-6" do
      bus[0xde00] = 0x20
      expect(bus.ultimax).to be(true)
    end
  end
end
