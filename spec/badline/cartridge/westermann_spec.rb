# frozen_string_literal: true

require "spec_helper"
require_relative "../../support/cartridge_builder"

describe Badline::Cartridge::Westermann do
  include CartridgeBuilder

  let(:basic) { 0x94 }
  let(:bus) { attached_bus(build_cartridge(11, [chip16k(bank: 0, fill: 0x10)], game: 0)) }

  it "boots in 16K mode" do
    expect(bus[0xa000]).to eq(0x11)
  end

  it "switches ROMH out on an I/O 2 read" do
    bus[0xdf00]
    expect(bus[0xa000]).to eq(basic)
  end

  it "ignores I/O 1 reads" do
    bus[0xde00]
    expect(bus[0xa000]).to eq(0x11)
  end
end
