# frozen_string_literal: true

require "spec_helper"
require_relative "../../support/cartridge_builder"

describe Badline::Cartridge::ActionReplay do
  include CartridgeBuilder

  let(:chips) { (0..3).map { |n| chip(bank: n, fill: 0x10 * (n + 1)) } }
  let(:cartridge) { build_cartridge(1, chips) }
  let(:bus) { attached_bus(cartridge) }

  it "boots in 8K mode with the first bank" do
    expect(bus[0x8000]).to eq(0x10)
  end

  it "selects the bank with bits 3 and 4" do
    bus[0xde00] = 0x18
    expect(bus[0x8000]).to eq(0x40)
  end

  it "decodes the register across I/O 1" do
    bus[0xde42] = 0x08
    expect(bus[0x8000]).to eq(0x20)
  end

  it "maps the bank at ROMH in 16K mode" do
    bus[0xde00] = 0x09
    expect(bus[0xa000]).to eq(0x20)
  end

  it "maps the bank at $E000 in Ultimax mode" do
    bus[0xde00] = 0x0b
    expect(bus[0xe000]).to eq(0x20)
  end

  it "switches the cartridge out with bit 1" do
    bus[0xde00] = 0x02
    expect(bus[0x8000]).to eq(0x00)
  end

  it "shows the last page of the ROM bank in I/O 2" do
    bus[0xde00] = 0x08
    expect(bus[0xdf10]).to eq(0x20)
  end

  it "latches the bus into the register on a read of I/O 1" do
    allow(bus.vic).to receive(:phi1_data).and_return(0x02)
    bus[0xde00]
    expect(bus[0x8000]).to eq(0x00)
  end

  context "with the RAM selected" do
    before { bus[0xde00] = 0x20 }

    it "reads the RAM at ROML" do
      bus[0x8123] = 0x5a
      expect(bus[0x8123]).to eq(0x5a)
    end

    it "writes through to the C64 RAM" do
      bus[0x8123] = 0x5a
      expect(bus.ram[0x8123]).to eq(0x5a)
    end

    it "shows the last page of the RAM in I/O 2" do
      bus[0x9f42] = 0x5a
      expect(bus[0xdf42]).to eq(0x5a)
    end

    it "takes writes in I/O 2" do
      bus[0xdf42] = 0x5a
      expect(bus[0x9f42]).to eq(0x5a)
    end

    it "keeps the RAM when the bank changes" do
      bus[0x8123] = 0x5a
      bus[0xde00] = 0x38
      expect(bus[0x8123]).to eq(0x5a)
    end
  end

  context "with the RAM selected and only EXROM released" do
    before { bus[0xde00] = 0x22 }

    it "reads the cartridge RAM and the C64 RAM together" do
      bus.ram[0x8123] = 0x0f
      cartridge.instance_variable_get(:@ram_data)[0x123] = 0xf0
      expect(bus[0x8123]).to eq(0xff)
    end

    it "writes both" do
      bus[0x8123] = 0x5a
      expect(bus.ram[0x8123]).to eq(0x5a)
    end
  end

  context "when switched off with bit 2" do
    before { bus[0xde00] = 0x06 }

    it "ignores the register" do
      bus[0xde00] = 0x00
      expect(bus[0x8000]).to eq(0x00)
    end

    it "reads open bus in I/O 2" do
      expect(bus[0xdf00]).to eq(bus.vic.phi1_data)
    end
  end

  describe "the freeze button" do
    it "pulls NMI" do
      cartridge.press_button
      expect(cartridge.nmi?).to be(true)
    end
  end

  context "when frozen" do
    before do
      bus[0xde00] = 0x3e
      cartridge.press_button
      cartridge.freeze!
    end

    it "enters Ultimax mode" do
      expect(bus.ultimax).to be(true)
    end

    it "maps the first bank at $E000" do
      expect(bus[0xe000]).to eq(0x10)
    end

    it "switches the register back on" do
      bus[0xde00] = 0x08
      expect(bus[0x8000]).to eq(0x20)
    end

    it "maps the RAM at ROML" do
      bus[0x8123] = 0x5a
      expect(bus[0x8123]).to eq(0x5a)
    end

    it "keeps writes to the RAM out of the C64 RAM" do
      bus.ram[0x8123] = 0x11
      bus[0x8123] = 0x5a
      expect(bus.ram[0x8123]).to eq(0x11)
    end

    it "holds NMI until bit 6 acknowledges the freeze" do
      bus[0xde00] = 0x03
      expect(cartridge.nmi?).to be(true)
    end

    it "lets go of NMI with bit 6" do
      bus[0xde00] = 0x40
      expect(cartridge.nmi?).to be(false)
    end

    it "returns to 8K mode on reset and lets go of NMI" do
      cartridge.reset
      expect([bus[0x8000], bus.ultimax, cartridge.nmi?]).to eq([0x10, false, false])
    end
  end
end
