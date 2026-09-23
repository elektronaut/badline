# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

describe Badline::Storage::CRTFile do
  subject(:crt) { described_class.new(path) }

  let(:dir) { Dir.mktmpdir }
  let(:path) { File.join(dir, "test.crt") }
  let(:chips) { [chip_packet(bank: 0, address: 0x8000, data: [0xaa] * 0x2000)] }
  let(:header) do
    "C64 CARTRIDGE   ".b + [0x40, 0x0100, 0, 0, 1].pack("NnnCC") +
      ("\x00" * 6) + "TEST CART".ljust(32, "\x00")
  end

  before { File.binwrite(path, header + chips.join) }

  after { FileUtils.remove_entry(dir) }

  def chip_packet(bank:, address:, data:, type: 0)
    "CHIP".b +
      [data.length + 0x10, type, bank, address, data.length].pack("Nn4") +
      data.pack("C*")
  end

  it "parses the hardware type" do
    expect(crt.hardware_type).to eq(0)
  end

  it "parses the EXROM line level" do
    expect(crt.exrom).to eq(0)
  end

  it "parses the GAME line level" do
    expect(crt.game).to eq(1)
  end

  it "parses the name" do
    expect(crt.name).to eq("TEST CART")
  end

  it "parses the chip load address" do
    expect(crt.chips.first.address).to eq(0x8000)
  end

  it "parses the chip data" do
    expect(crt.chips.first.data).to eq([0xaa] * 0x2000)
  end

  context "with multiple chip packets" do
    let(:chips) do
      [chip_packet(bank: 0, address: 0x8000, data: [0x01] * 0x2000),
       chip_packet(bank: 1, address: 0x8000, data: [0x02] * 0x2000)]
    end

    it "parses all banks" do
      expect(crt.chips.map(&:bank)).to eq([0, 1])
    end
  end

  context "with a packet length covering only the header" do
    let(:chips) do
      [chip_packet(bank: 0, address: 0x8000, data: [0x01] * 0x2000)
        .sub([0x2010].pack("N"), [0x10].pack("N"))]
    end

    it "advances past the chip data" do
      expect(crt.chips.length).to eq(1)
    end
  end

  context "with trailing bytes shorter than a chip header" do
    let(:chips) { [chip_packet(bank: 0, address: 0x8000, data: [0x01] * 0x2000), [0xff].pack("C") * 12] }

    it "ignores them" do
      expect(crt.chips.length).to eq(1)
    end
  end

  context "with a hardware subtype" do
    let(:header) do
      "C64 CARTRIDGE   ".b + [0x40, 0x0101, 57, 0, 1, 1].pack("NnnCCC") +
        ("\x00" * 5) + "TEST CART".ljust(32, "\x00")
    end

    it "parses the subtype" do
      expect(crt.subtype).to eq(1)
    end
  end

  context "with a bad signature" do
    let(:header) { "C64 FLOPPY DISK ".b + ("\x00" * 48) }

    it "raises a format error" do
      expect { crt }.to raise_error(described_class::FormatError)
    end
  end

  context "with a corrupt chip packet" do
    let(:chips) { ["JUNK#{"\x00" * 16}"] }

    it "raises a format error" do
      expect { crt }.to raise_error(described_class::FormatError)
    end
  end
end
