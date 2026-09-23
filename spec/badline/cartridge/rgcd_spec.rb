# frozen_string_literal: true

require "spec_helper"
require_relative "../../support/cartridge_builder"

describe Badline::Cartridge::RGCD do
  include CartridgeBuilder

  let(:chips) { (0..3).map { |n| chip(bank: n, fill: 0x10 + n) } }
  let(:bus) { attached_bus(build_cartridge(57, chips, subtype:)) }
  let(:subtype) { 0 }

  it "selects a bank on an I/O 1 write" do
    bus[0xde00] = 0x02
    expect(bus[0x8000]).to eq(0x12)
  end

  it "switches the ROM out with bit 3" do
    bus[0xde00] = 0x08
    expect(bus[0x8000]).to eq(0x00)
  end

  it "keeps the ROM out until reset" do
    bus[0xde00] = 0x08
    bus[0xde00] = 0x00
    expect(bus[0x8000]).to eq(0x00)
  end

  it "switches the ROM back in on reset" do
    bus[0xde00] = 0x08
    bus.cartridge.reset
    expect(bus[0x8000]).to eq(0x10)
  end

  context "when it is the Hucky board" do
    let(:subtype) { 1 }

    it "boots with the last bank" do
      expect(bus[0x8000]).to eq(0x13)
    end

    it "inverts the bank bits" do
      bus[0xde00] = 0x02
      expect(bus[0x8000]).to eq(0x11)
    end
  end
end
