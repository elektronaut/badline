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

  describe "the flash" do
    # The bank register drives the chip's upper address lines, so each
    # unlock cycle selects the bank its address falls in.
    def flash_write(offset, value)
      bus[0xde00] = 0xc0 | (offset >> 13)
      bus[0xe000 | (offset & 0x1fff)] = value
    end

    def unlocked(value)
      [[0x5555, 0xaa], [0x2aaa, 0x55], [0x5555, value]].each { |args| flash_write(*args) }
    end

    it "programs the selected bank through $E000 in flash mode" do
      unlocked(0xa0)
      flash_write(0x2123, 0x00)
      expect(bus.cartridge.flash.data[0x2123]).to eq(0x00)
    end

    it "reads the C64's memory in flash mode" do
      bus[0xde00] = 0xc0
      expect(bus[0xe000]).to eq(bus.kernal_rom.peek(0xe000))
    end

    it "leaves the C64's RAM under $E000 alone in flash mode" do
      bus[0xde00] = 0xc0
      bus[0xe000] = 0x12
      expect(bus.ram.peek(0xe000)).to eq(0x00)
    end

    it "sends $E000 writes to RAM outside flash mode" do
      bus[0xe000] = 0x12
      expect(bus.ram.peek(0xe000)).to eq(0x12)
    end

    it "reads the chip IDs through ROML in autoselect" do
      unlocked(0x90)
      bus[0xde00] = 0x00
      expect([bus[0x8000], bus[0x8001]]).to eq([0x01, 0xa4])
    end
  end
end
