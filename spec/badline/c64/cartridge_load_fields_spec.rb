# frozen_string_literal: true

require "spec_helper"
require_relative "../../../test/support/snapshot_cartridges"

# BL-CART as badline 0.14.0 wrote it, before the mappers saved their
# registers: each window by the name of the bank or view it shows.
describe Badline::C64::Cartridge, "#load_fields" do
  def legacy(type, exrom: 0, game: 1, **windows)
    crt = SnapshotCartridges.crt(type, SnapshotCartridges.banks(4) + SnapshotCartridges.banks(4, address: 0xa000))
    section = Badline::Snapshot::Keyed.section("BL-CART") do |out|
      out.bytes("crt", Badline::Storage::CRTFile.encode(crt)).int("exrom", exrom).int("game", game)
      windows.each { |key, value| write(out, key.to_s, value) }
    end
    Badline::Snapshot::Keyed::Reader.parse(section)
  end

  def write(out, key, value)
    case value
    when Integer then out.int(key, value)
    when true, false then out.bool(key, value)
    else out.text(key, value)
    end
  end

  def frozen_action_replay = legacy(1, exrom: 1, game: 0, roml: "isolated", romh: "rom0", rom: "rom0", io2_ram: true)

  def load(input)
    cartridge = SnapshotCartridges.attach(described_class.from_fields(input))
    cartridge.load_fields(input)
    cartridge
  end

  # The register the cartridge saves now, at `key`.
  def latch(cartridge, key)
    Badline::Snapshot::Keyed::Reader.parse(SnapshotCartridges.save(cartridge)).int(key, -1)
  end

  def banks(cartridge) = [cartridge.roml&.peek(0x8000), cartridge.romh&.peek(0xa000)]

  it "shows the bank a single-bank mapper named" do
    expect(banks(load(legacy(5, roml: "bank2")))).to eq([0x12, nil])
  end

  it "works out the bank register from it" do
    expect(latch(load(legacy(5, roml: "bank2")), "bank")).to eq(2)
  end

  it "takes erased ROM as the first bank the image leaves out" do
    expect(latch(load(legacy(17, roml: "empty")), "bank")).to eq(4)
  end

  it "works out the bank of a mapper with two banks of ROM" do
    expect(latch(load(legacy(8, game: 0, roml: "roml3", romh: "romh3")), "bank")).to eq(3)
  end

  it "reads the ROMH bank of a Zaxxon as it did" do
    expect(load(legacy(18, game: 0, high_bank: 1)).romh.peek(0xa000)).to eq(0x11)
  end

  it "works out the Action Replay's register after a freeze" do
    expect(latch(load(frozen_action_replay), "control")).to eq(Badline::C64::Cartridge::ActionReplay::FREEZE_CONTROL)
  end

  it "works out the Pagefox's register for its RAM" do
    expect(latch(load(legacy(53, game: 0, roml: "ram0", romh: "ram1")), "control")).to eq(0x08)
  end

  it "reads them without a word" do
    input = frozen_action_replay
    load(input)
    expect(input.report.lines(verbose: true)).to be_empty
  end
end
