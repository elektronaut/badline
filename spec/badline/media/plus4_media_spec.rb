# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

describe Badline::Media::Plus4Media do
  let(:dir) { Dir.mktmpdir }

  after { FileUtils.remove_entry(dir) }

  # The bank and address of each chip.
  def slots(chips) = chips.map { |chip| [chip.bank, chip.address] }

  describe ".rom_chips" do
    it "puts up to 16K in cartridge 1's low slot" do
      expect(slots(described_class.rom_chips([0x4c] * 0x2000))).to eq([[0, 0x8000]])
    end

    it "fills cartridge 1's high slot from a 32K image's second half" do
      chips = described_class.rom_chips(([0x11] * 0x4000) + ([0x22] * 0x4000))
      expect(chips.map { |chip| [chip.address, chip.data.first, chip.data.length] })
        .to eq([[0x8000, 0x11, 0x4000], [0xc000, 0x22, 0x4000]])
    end

    it "puts an image in the slot it names" do
      expect(slots(described_class.rom_chips([0x4c] * 0x4000, slot: "c2hi"))).to eq([[1, 0xc000]])
    end

    it "refuses an image bigger than both slots" do
      expect { described_class.rom_chips([0] * 0x8001) }.to raise_error(ArgumentError, /no Plus.4 cartridge/)
    end

    it "refuses an image bigger than the slot it names" do
      expect { described_class.rom_chips([0] * 0x4001, slot: "c1hi") }.to raise_error(ArgumentError, /16K/)
    end

    it "refuses a slot it doesn't know" do
      expect { described_class.rom_chips([0], slot: "c3lo") }.to raise_error(ArgumentError, /c3lo/)
    end
  end

  describe ".cartridge_chips" do
    it "reads a raw .bin image" do
      path = File.join(dir, "game.BIN").tap { |file| File.binwrite(file, ([0x4c] * 0x4000).pack("C*")) }
      expect(slots(described_class.cartridge_chips(path, slot: "c2lo"))).to eq([[1, 0x8000]])
    end

    it "reads the chips of a PLUS4 CARTRIDGE .crt, cartridge 2's in bank 1" do
      path = File.join(dir, "game.crt")
      File.binwrite(path, "PLUS4 CARTRIDGE ".b + [0x40, 0x0200, 0, 0, 0].pack("NnnCC") + ("\x00" * 38) +
                          "CHIP".b + [0x1010, 0, 1, 0xc000, 0x1000].pack("Nn4") + ([0x42] * 0x1000).pack("C*"))
      expect(slots(described_class.cartridge_chips(path))).to eq([[1, 0xc000]])
    end
  end
end
