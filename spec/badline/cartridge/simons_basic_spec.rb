# frozen_string_literal: true

require "spec_helper"
require_relative "../../support/cartridge_builder"

describe Badline::Cartridge::SimonsBasic do
  include CartridgeBuilder

  let(:basic) { 0x94 }
  let(:bus) do
    attached_bus(build_cartridge(4, [chip(bank: 0, fill: 0x10), chip(bank: 0, fill: 0x11, address: 0xa000)]))
  end

  it "boots in 16K mode" do
    expect(bus[0xa000]).to eq(0x11)
  end

  it "switches ROMH out on an I/O 1 read" do
    bus[0xde00]
    expect(bus[0xa000]).to eq(basic)
  end

  it "keeps ROML in after an I/O 1 read" do
    bus[0xde00]
    expect(bus[0x8000]).to eq(0x10)
  end

  it "reads open bus from I/O 1" do
    expect(bus[0xde00]).to eq(bus.vic.phi1_data)
  end

  it "switches ROMH back in on an I/O 1 write" do
    bus[0xde00]
    bus[0xde00] = 0
    expect(bus[0xa000]).to eq(0x11)
  end
end
