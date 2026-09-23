# frozen_string_literal: true

require "spec_helper"
require_relative "../../support/cartridge_builder"

describe Badline::Cartridge::Pagefox do
  include CartridgeBuilder

  let(:chips) { (0..3).map { |n| chip16k(bank: n, fill: 0x10 * (n + 1)) } }
  let(:bus) { attached_bus(build_cartridge(53, chips, game: 0)) }

  it "boots with the first EPROM half in 16K mode" do
    expect(bus[0xa000]).to eq(0x11)
  end

  it "selects the EPROM half with bit 1" do
    bus[0xde80] = 0x02
    expect(bus[0x8000]).to eq(0x20)
  end

  it "selects the second EPROM with bit 2" do
    bus[0xde80] = 0x04
    expect(bus[0x8000]).to eq(0x30)
  end

  it "ignores writes below $DE80" do
    bus[0xde00] = 0x04
    expect(bus[0x8000]).to eq(0x10)
  end

  it "switches the cartridge out with bit 4" do
    bus[0xde80] = 0x10
    expect(bus[0x8000]).to eq(0x00)
  end

  it "reads open bus from the empty chip select" do
    bus[0xde80] = 0x0c
    expect(bus[0x8000]).to eq(bus.vic.phi1_data)
  end

  context "with the RAM selected" do
    before { bus[0xde80] = 0x08 }

    it "stores writes in the cartridge RAM" do
      bus[0xa123] = 0x5a
      expect(bus[0xa123]).to eq(0x5a)
    end

    it "writes through to the C64 RAM" do
      bus[0x8123] = 0x5a
      expect(bus.ram[0x8123]).to eq(0x5a)
    end

    it "takes writes while the $01 lines bank it out" do
      bus[0x01] = 0x35
      bus[0x8123] = 0x5a
      bus[0x01] = 0x37
      expect(bus[0x8123]).to eq(0x5a)
    end

    it "keeps each half separate" do
      bus[0x8000] = 0x5a
      bus[0xde80] = 0x0a
      expect(bus[0x8000]).to eq(0x00)
    end
  end
end
