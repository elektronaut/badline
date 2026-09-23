# frozen_string_literal: true

require "spec_helper"
require_relative "../../support/cartridge_builder"

describe Badline::Cartridge::AtomicPower do
  include CartridgeBuilder

  let(:chips) { (0..3).map { |n| chip(bank: n, fill: 0x10 * (n + 1)) } }
  let(:cartridge) { build_cartridge(9, chips) }
  let(:bus) { attached_bus(cartridge) }

  it "maps the RAM at ROML like the Action Replay" do
    bus[0xde00] = 0x20
    bus[0x8123] = 0x5a
    expect(bus[0x8123]).to eq(0x5a)
  end

  it "never shows the VIC Ultimax mode" do
    bus[0xde00] = 0x03
    expect(bus.phi1_ultimax).to be(false)
  end

  context "with the RAM selected and only EXROM released" do
    before { bus[0xde00] = 0x2a }

    it "maps the ROM bank at ROML in 16K mode" do
      expect(bus[0x8000]).to eq(0x20)
    end

    it "maps the RAM at ROMH" do
      bus[0xa123] = 0x5a
      expect(bus[0xa123]).to eq(0x5a)
    end

    it "keeps writes to ROMH out of the C64 RAM" do
      bus.ram[0xa123] = 0x11
      bus[0xa123] = 0x5a
      expect(bus.ram[0xa123]).to eq(0x11)
    end

    it "shows the RAM in I/O 2" do
      bus[0xbf42] = 0x5a
      expect(bus[0xdf42]).to eq(0x5a)
    end
  end

  it "keeps the Action Replay mapping with bit 6 set" do
    bus[0xde00] = 0x62
    expect(bus[0x8000]).to eq(bus.ram[0x8000])
  end
end
