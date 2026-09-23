# frozen_string_literal: true

require "spec_helper"
require_relative "../../support/cartridge_builder"

describe Badline::Cartridge::GameSystem do
  include CartridgeBuilder

  let(:chips) { [chip(bank: 0, fill: 0x10), chip(bank: 5, fill: 0x15)] }
  let(:bus) { attached_bus(build_cartridge(15, chips)) }

  it "selects the bank from the address of an I/O 1 write" do
    bus[0xde05] = 0x00
    expect(bus[0x8000]).to eq(0x15)
  end

  it "selects the bank from the address of an I/O 1 read" do
    bus[0xde45]
    expect(bus[0x8000]).to eq(0x15)
  end

  it "fills missing banks with $FF" do
    bus[0xde03] = 0x00
    expect(bus[0x8000]).to eq(0xff)
  end

  it "selects the first bank on reset" do
    bus[0xde05] = 0
    bus.cartridge.reset
    expect(bus[0x8000]).to eq(0x10)
  end
end
