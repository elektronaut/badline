# frozen_string_literal: true

require "spec_helper"
require_relative "../../support/cartridge_builder"

describe Badline::Cartridge::Zaxxon do
  include CartridgeBuilder

  let(:chips) do
    [chip(bank: 0, fill: 0x10, size: 0x1000),
     chip(bank: 0, fill: 0x20, address: 0xa000), chip(bank: 1, fill: 0x21, address: 0xa000)]
  end
  let(:bus) { attached_bus(build_cartridge(18, chips, game: 0)) }

  it "mirrors the 4K ROML at $9000" do
    expect(bus[0x9000]).to eq(0x10)
  end

  it "selects the second ROMH bank on a read at $9000-$9FFF" do
    bus[0x9000]
    expect(bus[0xa000]).to eq(0x21)
  end

  it "selects the first ROMH bank on a read at $8000-$8FFF" do
    bus[0x9000]
    bus[0x8fff]
    expect(bus[0xa000]).to eq(0x20)
  end

  it "selects the first ROMH bank on reset" do
    bus[0x9000]
    bus.cartridge.reset
    expect(bus[0xa000]).to eq(0x20)
  end
end
