# frozen_string_literal: true

require "spec_helper"
require_relative "../../support/cartridge_builder"

describe Badline::Cartridge::Dinamic do
  include CartridgeBuilder

  let(:chips) { [chip(bank: 0, fill: 0x10), chip(bank: 3, fill: 0x13)] }
  let(:bus) { attached_bus(build_cartridge(17, chips)) }

  it "selects the bank from the address of an I/O 1 read" do
    bus[0xde03]
    expect(bus[0x8000]).to eq(0x13)
  end

  it "ignores reads above $DE0F" do
    bus[0xde13]
    expect(bus[0x8000]).to eq(0x10)
  end

  it "ignores writes" do
    bus[0xde03] = 0x03
    expect(bus[0x8000]).to eq(0x10)
  end
end
