# frozen_string_literal: true

require "spec_helper"
require_relative "../../support/cartridge_builder"

describe Badline::Cartridge::RexUtility do
  include CartridgeBuilder

  let(:bus) { attached_bus(build_cartridge(12, [chip(bank: 0, fill: 0x10)])) }

  it "boots with the ROM in" do
    expect(bus[0x8000]).to eq(0x10)
  end

  it "switches the ROM out on a read below $DFC0" do
    bus[0xdfbf]
    expect(bus[0x8000]).to eq(0x00)
  end

  it "switches the ROM back in on a read from $DFC0" do
    bus[0xdf00]
    bus[0xdfc0]
    expect(bus[0x8000]).to eq(0x10)
  end

  it "switches the ROM back in on reset" do
    bus[0xdf00]
    bus.cartridge.reset
    expect(bus[0x8000]).to eq(0x10)
  end
end
