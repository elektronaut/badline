# frozen_string_literal: true

require "spec_helper"
require_relative "../../support/cartridge_builder"

describe Badline::Cartridge::FunPlay do
  include CartridgeBuilder

  # The CRT numbers banks by register value: $08 selects bank 1, $01 bank 8.
  let(:chips) { [chip(bank: 0x00, fill: 0x10), chip(bank: 0x08, fill: 0x11), chip(bank: 0x01, fill: 0x18)] }
  let(:bus) { attached_bus(build_cartridge(7, chips)) }

  it "boots with bank 0" do
    expect(bus[0x8000]).to eq(0x10)
  end

  it "selects a bank from bits 3-5" do
    bus[0xde00] = 0x08
    expect(bus[0x8000]).to eq(0x11)
  end

  it "selects a bank from bit 0" do
    bus[0xde00] = 0x01
    expect(bus[0x8000]).to eq(0x18)
  end

  it "switches the ROM out with $86" do
    bus[0xde00] = 0x86
    expect(bus[0x8000]).to eq(0x00)
  end

  it "selects the first bank in 8K mode on reset" do
    bus[0xde00] = 0x86
    bus.cartridge.reset
    expect(bus[0x8000]).to eq(0x10)
  end
end
