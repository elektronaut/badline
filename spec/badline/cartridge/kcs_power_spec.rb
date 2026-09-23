# frozen_string_literal: true

require "spec_helper"
require_relative "../../support/cartridge_builder"

describe Badline::Cartridge::KCSPower do
  include CartridgeBuilder

  let(:cartridge) { build_cartridge(2, [chip16k(bank: 0, fill: 0x10)], game: 0) }
  let(:bus) { attached_bus(cartridge) }

  it "boots in 16K mode" do
    expect([bus[0x8000], bus[0xa000]]).to eq([0x10, 0x11])
  end

  it "shows the second last page of ROML in I/O 1" do
    expect(bus[0xde00]).to eq(0x10)
  end

  it "switches to 8K mode on a read of I/O 1 with address bit 1 clear" do
    bus[0xde00]
    expect(bus[0xa000]).to eq(0x94)
  end

  it "switches the cartridge out on a read of I/O 1 with address bit 1 set" do
    bus[0xde02]
    expect(bus[0x8000]).to eq(0x00)
  end

  it "switches to 16K mode on a write to I/O 1 with address bit 1 clear" do
    bus[0xde02]
    bus[0xde80] = 0
    expect(bus[0xa000]).to eq(0x11)
  end

  it "switches to Ultimax mode on a write to I/O 1 with address bit 1 set" do
    bus[0xde02] = 0
    expect(bus.ultimax).to be(true)
  end

  it "keeps 128 bytes of RAM in I/O 2" do
    bus[0xdf7f] = 0x5a
    expect(bus[0xdf7f]).to eq(0x5a)
  end

  it "reads EXROM in bit 7 and GAME in bit 6 of the upper half of I/O 2" do
    bus[0xde02]
    expect(bus[0xdf80] & 0xc0).to eq(0xc0)
  end

  it "reads both lines low in 16K mode" do
    expect(bus[0xdf80] & 0xc0).to eq(0x00)
  end

  describe "the freeze button" do
    before { cartridge.press_button }

    it "pulls NMI" do
      expect(cartridge.nmi?).to be(true)
    end

    it "switches to Ultimax and lets go of NMI on the freeze" do
      cartridge.freeze!
      expect([bus.ultimax, cartridge.nmi?]).to eq([true, false])
    end
  end
end
