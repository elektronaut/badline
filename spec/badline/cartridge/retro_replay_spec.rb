# frozen_string_literal: true

require "spec_helper"
require_relative "../../support/cartridge_builder"

describe Badline::Cartridge::RetroReplay do
  include CartridgeBuilder

  let(:chips) { (0..7).map { |n| chip(bank: n, fill: 0x10 * (n + 1)) } }
  let(:subtype) { 0 }
  let(:cartridge) { build_cartridge(36, chips, subtype:) }
  let(:bus) { attached_bus(cartridge) }

  it "boots in 8K mode with the first bank" do
    expect(bus[0x8000]).to eq(0x10)
  end

  it "selects the bank with bits 3, 4 and 7" do
    bus[0xde00] = 0x88
    expect(bus[0x8000]).to eq(0x60)
  end

  it "selects the bank through $DE01" do
    bus[0xde01] = 0x10
    expect(bus[0x8000]).to eq(0x30)
  end

  it "reads the bank back from $DE00" do
    bus[0xde00] = 0x98
    expect(bus[0xde00]).to eq(0x98)
  end

  it "maps nothing at ROML in 16K mode without the RAM" do
    bus[0xde00] = 0x01
    expect(bus[0x8000]).to eq(bus.vic.phi1_data)
  end

  it "shows the last page of the ROM bank in I/O 2" do
    bus[0xde00] = 0x08
    expect(bus[0xdf10]).to eq(0x20)
  end

  it "reads nothing in I/O 2 in 16K mode without the RAM" do
    bus[0xde00] = 0x01
    expect(bus[0xdf00]).to eq(bus.vic.phi1_data)
  end

  it "reads open bus in I/O 1 above the registers" do
    expect(bus[0xde10]).to eq(bus.vic.phi1_data)
  end

  it "keeps the VIC out of Ultimax mode" do
    bus[0xde00] = 0x03
    expect(bus.phi1_ultimax).to be(false)
  end

  it "switches the registers off with bit 2" do
    bus[0xde00] = 0x06
    bus[0xde00] = 0x00
    expect(bus[0x8000]).to eq(0x00)
  end

  context "with the RAM selected in 8K mode" do
    before { bus[0xde00] = 0x20 }

    it "leaves writes to ROML to the C64 RAM" do
      bus[0x8123] = 0x5a
      expect(bus[0x8123]).to eq(0x00)
    end

    it "takes writes in I/O 2" do
      bus[0xdf42] = 0x5a
      expect(bus[0x9f42]).to eq(0x5a)
    end

    it "banks the I/O RAM with AllowBank" do
      bus[0xde01] = 0x02
      bus[0xdf42] = 0x5a
      bus[0xde00] = 0x28
      expect(bus[0xdf42]).to eq(0x00)
    end

    it "keeps the I/O RAM in the first bank without AllowBank" do
      bus[0xdf42] = 0x5a
      bus[0xde00] = 0x28
      expect(bus[0xdf42]).to eq(0x5a)
    end

    it "moves the I/O RAM to I/O 1 with the REU-compatible map" do
      bus[0xde01] = 0x40
      bus[0xde42] = 0x5a
      expect(bus[0x9e42]).to eq(0x5a)
    end

    it "reads the I/O RAM in I/O 1 with the REU-compatible map" do
      bus[0xde01] = 0x40
      bus[0xde42] = 0x5a
      expect(bus[0xde42]).to eq(0x5a)
    end
  end

  context "with the RAM selected in Ultimax mode" do
    before { bus[0xde00] = 0x23 }

    it "takes writes at ROML" do
      bus[0x8123] = 0x5a
      expect(bus[0x8123]).to eq(0x5a)
    end

    it "keeps writes to ROML out of the C64 RAM" do
      bus.ram[0x8123] = 0x11
      bus[0x8123] = 0x5a
      expect(bus.ram[0x8123]).to eq(0x11)
    end
  end

  it "keeps the $DE01 bits across a reset" do
    bus[0xde01] = 0x02
    cartridge.reset
    expect(bus[0xde00] & 0x02).to eq(0x02)
  end

  it "writes the $DE01 bits once only" do
    bus[0xde01] = 0x02
    bus[0xde01] = 0x40
    expect(bus[0xde00] & 0x42).to eq(0x02)
  end

  it "maps the RAM in I/O 2 with only EXROM released" do
    bus[0xde00] = 0x22
    bus[0xdf42] = 0x5a
    expect(bus[0xdf42]).to eq(0x5a)
  end

  describe "the freeze button" do
    it "pulls NMI" do
      cartridge.press_button
      expect(cartridge.nmi?).to be(true)
    end

    it "shows in bit 2 of $DE00 while pressed" do
      cartridge.press_button
      expect(bus[0xde00] & 0x04).to eq(0x04)
    end

    it "clears bit 2 of $DE00 on release" do
      cartridge.press_button
      cartridge.release_button
      expect(bus[0xde00] & 0x04).to eq(0x00)
    end

    it "leaves NMI alone with NoFreeze" do
      bus[0xde01] = 0x04
      cartridge.press_button
      expect(cartridge.nmi?).to be(false)
    end
  end

  context "when frozen" do
    before do
      bus[0xde00] = 0x98
      cartridge.press_button
      cartridge.freeze!
    end

    it "enters Ultimax mode on both halves of the cycle" do
      expect([bus.ultimax, bus.phi1_ultimax]).to eq([true, true])
    end

    it "maps the first bank at $E000" do
      expect(bus[0xe000]).to eq(0x10)
    end

    it "maps nothing at ROML" do
      expect(bus[0x8000]).to eq(bus.vic.phi1_data)
    end

    it "stays in Ultimax mode until bit 6 acknowledges the freeze" do
      bus[0xde00] = 0x00
      expect(bus.ultimax).to be(true)
    end

    it "takes the VIC out of Ultimax mode on a register write" do
      bus[0xde00] = 0x00
      expect(bus.phi1_ultimax).to be(false)
    end

    it "reads nothing at ROML with the RAM selected" do
      bus[0xde00] = 0x20
      expect(bus[0x8000]).to eq(bus.vic.phi1_data)
    end

    it "takes writes to the RAM at ROML while reading nothing there" do
      bus[0xde00] = 0x20
      bus[0x8123] = 0x5a
      bus[0xde00] = 0x63
      expect(bus[0x8123]).to eq(0x5a)
    end

    it "leaves the freeze on reset" do
      cartridge.reset
      expect([bus.ultimax, cartridge.nmi?, bus[0x8000]]).to eq([false, false, 0x10])
    end

    it "leaves the freeze with bit 6" do
      bus[0xde00] = 0x40
      expect([bus.ultimax, cartridge.nmi?]).to eq([false, false])
    end
  end

  context "with the Nordic Replay" do
    let(:subtype) { 1 }

    it "writes the RAM at ROML through to the C64 RAM in 8K mode" do
      bus[0xde00] = 0x20
      bus[0x8123] = 0x5a
      expect([bus[0x8123], bus.ram[0x8123]]).to eq([0x5a, 0x5a])
    end

    it "maps the ROM at ROML with only EXROM released" do
      bus[0xde00] = 0x2a
      expect(bus[0x8000]).to eq(0x20)
    end

    it "maps the RAM at ROMH with only EXROM released" do
      bus[0xde00] = 0x22
      bus[0xa123] = 0x5a
      expect(bus[0xa123]).to eq(0x5a)
    end
  end
end
