# frozen_string_literal: true

require "spec_helper"
require_relative "../../support/cartridge_builder"

describe Badline::Cartridge::EasyFlash do
  include CartridgeBuilder

  let(:chips) do
    (0..2).flat_map do |n|
      [chip(bank: n, fill: 0x10 + n), chip(bank: n, fill: 0x20 + n, address: 0xa000)]
    end
  end
  let(:bus) { attached_bus(build_cartridge(32, chips, exrom: 1, game: 0)) }

  it "boots in Ultimax mode" do
    expect(bus.ultimax).to be(true)
  end

  it "maps ROMH at $E000 in Ultimax mode" do
    expect(bus[0xe000]).to eq(0x20)
  end

  it "selects the bank through $DE00" do
    bus[0xde00] = 0x02
    expect(bus[0xe000]).to eq(0x22)
  end

  it "selects 16K mode through $DE02" do
    bus[0xde02] = 0x07
    expect(bus[0xa000]).to eq(0x20)
  end

  it "selects 8K mode through $DE02" do
    bus[0xde02] = 0x06
    expect(bus[0xa000]).to eq(0x94)
  end

  it "switches the cartridge out through $DE02" do
    bus[0xde02] = 0x04
    expect(bus[0x8000]).to eq(0x00)
  end

  it "keeps GAME low while bit 2 is clear" do
    bus[0xde02] = 0x02
    expect(bus[0xa000]).to eq(0x20)
  end

  it "reads open bus from the unmapped Ultimax space" do
    expect(bus[0xa000]).to eq(bus.vic.phi1_data)
  end

  it "drives the LED from bit 7" do
    bus[0xde02] = 0x87
    expect(bus.cartridge.led?).to be(true)
  end

  it "keeps 256 bytes of RAM at $DF00" do
    bus[0xdf42] = 0x5a
    expect(bus[0xdf42]).to eq(0x5a)
  end

  it "reads open bus from I/O 1" do
    expect(bus[0xde00]).to eq(bus.vic.phi1_data)
  end
end
