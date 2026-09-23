# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require_relative "../../support/cartridge_builder"

describe Badline::Cartridge::EasyFlash do
  include CartridgeBuilder

  let(:chips) do
    (0..2).flat_map do |n|
      [chip(bank: n, fill: 0x10 + n), chip(bank: n, fill: 0x20 + n, address: 0xa000)]
    end
  end
  let(:bus) { attached_bus(build_cartridge(32, chips, exrom: 1, game: 0)) }

  it "boots in Ultimax mode" do
    expect(bus.ultimax).to be(true)
  end

  it "maps ROMH at $E000 in Ultimax mode" do
    expect(bus[0xe000]).to eq(0x20)
  end

  it "selects the bank through $DE00" do
    bus[0xde00] = 0x02
    expect(bus[0xe000]).to eq(0x22)
  end

  it "selects 16K mode through $DE02" do
    bus[0xde02] = 0x07
    expect(bus[0xa000]).to eq(0x20)
  end

  it "selects 8K mode through $DE02" do
    bus[0xde02] = 0x06
    expect(bus[0xa000]).to eq(0x94)
  end

  it "switches the cartridge out through $DE02" do
    bus[0xde02] = 0x04
    expect(bus[0x8000]).to eq(0x00)
  end

  it "keeps GAME low while bit 2 is clear" do
    bus[0xde02] = 0x02
    expect(bus[0xa000]).to eq(0x20)
  end

  it "reads open bus from the unmapped Ultimax space" do
    expect(bus[0xa000]).to eq(bus.vic.phi1_data)
  end

  it "drives the LED from bit 7" do
    bus[0xde02] = 0x87
    expect(bus.cartridge.led?).to be(true)
  end

  it "keeps 256 bytes of RAM at $DF00" do
    bus[0xdf42] = 0x5a
    expect(bus[0xdf42]).to eq(0x5a)
  end

  it "reads open bus from I/O 1" do
    expect(bus[0xde00]).to eq(bus.vic.phi1_data)
  end

  it "clears the bank and mode registers on reset" do
    bus[0xde00] = 0x02
    bus[0xde02] = 0x07
    bus.cartridge.reset
    expect([bus.ultimax, bus[0xe000]]).to eq([true, 0x20])
  end

  it "keeps the RAM over a reset" do
    bus[0xdf42] = 0x5a
    bus.cartridge.reset
    expect(bus[0xdf42]).to eq(0x5a)
  end

  describe "the flash" do
    def flash_command(base, *writes)
      writes.each { |offset, value| bus[base | offset] = value }
    end

    def program(base, addr, value)
      flash_command(base, [0x555, 0xaa], [0x2aa, 0x55], [0x555, 0xa0])
      bus[addr] = value
    end

    it "programs ROML through $8000 in Ultimax mode" do
      bus[0xde02] = 0x05
      program(0x8000, 0x8123, 0x00)
      expect(bus.cartridge.low_flash.data[0x0123]).to eq(0x00)
    end

    it "programs ROMH through $E000 in the selected bank" do
      bus[0xde00] = 0x02
      program(0xe000, 0xe123, 0x02)
      expect(bus.cartridge.high_flash.data[0x4123]).to eq(0x02)
    end

    it "ignores writes in 16K mode" do
      bus[0xde02] = 0x07
      program(0x8000, 0x8123, 0x00)
      expect(bus.cartridge.low_flash.data[0x0123]).to eq(0x10)
    end

    it "reads the chip IDs in autoselect" do
      flash_command(0xe000, [0x555, 0xaa], [0x2aa, 0x55], [0x555, 0x90])
      expect([bus[0xe000], bus[0xe001]]).to eq([0x01, 0xa4])
    end

    it "reads the array again after a reset" do
      flash_command(0xe000, [0x555, 0xaa], [0x2aa, 0x55], [0x555, 0x90], [0x000, 0xf0])
      expect(bus[0xe000]).to eq(0x20)
    end

    it "keeps the autoselect codes to its own chip" do
      flash_command(0xe000, [0x555, 0xaa], [0x2aa, 0x55], [0x555, 0x90])
      expect(bus[0x8000]).to eq(0x10)
    end
  end

  describe "#save_crt" do
    let(:dir) { Dir.mktmpdir }
    let(:path) { File.join(dir, "saved.crt") }
    let(:saved) { Badline::Storage::CRTFile.new(path) }

    before do
      bus[0xde02] = 0x05
      [[0x8555, 0xaa], [0x82aa, 0x55], [0x8555, 0xa0], [0x8000, 0x00]].each { |addr, value| bus[addr] = value }
      bus.cartridge.save_crt(path)
    end

    after { FileUtils.remove_entry(dir) }

    it "writes the banks that aren't blank" do
      expect(saved.chips.map { |chip| [chip.bank, chip.address] })
        .to eq([[0, 0x8000], [0, 0xa000], [1, 0x8000], [1, 0xa000], [2, 0x8000], [2, 0xa000]])
    end

    it "writes what was programmed" do
      expect(saved.chips.first.data.first(2)).to eq([0x00, 0x10])
    end
  end
end
