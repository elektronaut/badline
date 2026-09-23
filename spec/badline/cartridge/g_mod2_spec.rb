# frozen_string_literal: true

require "spec_helper"
require_relative "../../support/cartridge_builder"

describe Badline::Cartridge::GMod2 do
  include CartridgeBuilder

  let(:chips) { [chip(bank: 0, fill: 0x10), chip(bank: 0x3f, fill: 0x4f)] }
  let(:bus) { attached_bus(build_cartridge(60, chips)) }

  it "selects one of 64 banks" do
    bus[0xde00] = 0x3f
    expect(bus[0x8000]).to eq(0x4f)
  end

  it "switches the ROM out when the EEPROM is selected" do
    bus[0xde00] = 0x40
    expect(bus[0x8000]).to eq(0x00)
  end
end
