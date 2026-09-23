# frozen_string_literal: true

require "spec_helper"
require_relative "../../support/cartridge_builder"

describe Badline::Cartridge::FinalCartridge3 do
  include CartridgeBuilder

  let(:banks) { 4 }
  let(:chips) { (0...banks).map { |n| chip16k(bank: n, fill: 0x10 * (n + 1)) } }
  let(:cartridge) { build_cartridge(3, chips, game: 0) }
  let(:bus) { attached_bus(cartridge) }

  it "boots in 16K mode with the first bank" do
    expect([bus[0x8000], bus[0xa000]]).to eq([0x10, 0x11])
  end

  it "selects the bank through $DFFF" do
    bus[0xdfff] = 0x42
    expect(bus[0x8000]).to eq(0x30)
  end

  it "ignores writes elsewhere in I/O 2" do
    bus[0xdffe] = 0x42
    expect(bus[0x8000]).to eq(0x10)
  end

  it "shows the last two pages of the ROML bank in I/O" do
    bus[0xdfff] = 0x41
    expect([bus[0xde00], bus[0xdf00]]).to eq([0x20, 0x20])
  end

  it "sets EXROM with bit 4" do
    bus[0xdfff] = 0x50
    expect(bus[0xe000]).to eq(0x11)
  end

  it "sets GAME with bit 5" do
    bus[0xdfff] = 0x60
    expect(bus[0xa000]).to eq(0x94)
  end

  it "switches the cartridge out with both lines high" do
    bus[0xdfff] = 0x70
    expect(bus[0x8000]).to eq(0x00)
  end

  it "hides the register with bit 7" do
    bus[0xdfff] = 0xc0
    bus[0xdfff] = 0x41
    expect(bus[0x8000]).to eq(0x10)
  end

  it "pulls NMI without a freeze when bit 6 is clear" do
    bus[0xdfff] = 0x00
    expect([cartridge.nmi?, bus.ultimax]).to eq([true, false])
  end

  context "with the sixteen banks of the III+" do
    let(:banks) { 16 }

    it "selects the bank from bits 0-3" do
      bus[0xdfff] = 0x49
      expect(bus[0x8000]).to eq(0xa0)
    end
  end

  context "when frozen" do
    before do
      bus[0xdfff] = 0xc2
      cartridge.press_button
      cartridge.freeze!
    end

    it "enters Ultimax mode with the bank it had" do
      expect([bus.ultimax, bus[0xe000]]).to eq([true, 0x31])
    end

    it "keeps the VIC out of Ultimax mode" do
      expect(bus.phi1_ultimax).to be(false)
    end

    it "shows the register again" do
      bus[0xdfff] = 0x40
      expect(bus[0x8000]).to eq(0x10)
    end

    it "holds NMI" do
      expect(cartridge.nmi?).to be(true)
    end

    it "returns to 16K mode with the first bank on reset" do
      cartridge.reset
      expect([bus.ultimax, cartridge.nmi?, bus[0xa000]]).to eq([false, false, 0x11])
    end

    it "lets go of NMI with bit 6" do
      bus[0xdfff] = 0x40
      expect(cartridge.nmi?).to be(false)
    end
  end
end
