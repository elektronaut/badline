# frozen_string_literal: true

require "spec_helper"
require_relative "../support/cartridge_builder"
require_relative "../support/snapshot_scenarios"

describe Badline::Cartridge, "#save_state" do
  include CartridgeBuilder
  include SnapshotScenarios

  # A cartridge built from a parsed CRT file, as Media attaches one.
  def cartridge(type, chips = banks(4) + banks(4, address: 0xa000), **)
    image = CartridgeBuilder::CRT.new(hardware_type: type, subtype: 0, exrom: 0, game: 1, name: "TEST", chips:)
    crt = Badline::Storage::CRTFile.new(bytes: Badline::Storage::CRTFile.encode(image))
    attach(described_class.from_crt(crt, **))
  end

  def attach(cartridge)
    cartridge.clock = -> { 100 }
    cartridge.connect(ram: Badline::Memory.new, open_bus: nil)
    cartridge
  end

  def banks(count, address: 0x8000) = Array.new(count) { |n| chip(bank: n, fill: 0x10 + n, address:) }

  def setup_of(cartridge)
    out = Badline::Snapshot::StateWriter.new
    cartridge.save_setup(out)
    Badline::Snapshot::StateReader.new(out.state)
  end

  # The cartridge built afresh from its setup, with the state put in.
  def rebuilt(cartridge)
    round_trip(cartridge, attach(described_class.from_setup(setup_of(cartridge))))
  end

  def pokes(cartridge, writes)
    writes.each { |addr, value| cartridge.poke(addr, value) }
    cartridge
  end

  context "with an EasyFlash programming a byte" do
    let(:easy_flash) do
      pokes(cartridge(32), [[0xde00, 1], [0xdf10, 0x42]]).tap do |cart|
        [[0xe555, 0xaa], [0xe2aa, 0x55], [0xe555, 0xa0], [0xe100, 0x12]].each { |write| cart.romh.poke(*write) }
      end
    end

    it "builds the same image from its setup" do
      crt = ->(cart) { cart.instance_variable_get(:@crt) }
      expect(state_differences(crt[described_class.from_setup(setup_of(easy_flash))], crt[easy_flash])).to be_empty
    end

    it "comes back with its flash busy, its bank and its RAM" do
      expect(state_differences(easy_flash, rebuilt(easy_flash))).to be_empty
    end

    it "maps the flash window its bank selects" do
      copy = rebuilt(easy_flash)
      expect(copy.roml).to equal(copy.low_flash.window(0x2000))
    end
  end

  it "keeps an Action Replay frozen, with its RAM" do
    replay = pokes(cartridge(1), [[0xde00, 0x20], [0xdf10, 0x5a]]).tap(&:press_button).tap(&:freeze!)
    expect(state_differences(replay, rebuilt(replay))).to be_empty
  end

  it "keeps a Retro Replay's jumpers, registers and RAM" do
    replay = pokes(cartridge(36, banks(2), flash_jumper: true), [[0xde01, 0x22], [0xde00, 0x20]])
    replay.roml.poke(0x8010, 0x33)
    expect(state_differences(replay, rebuilt(replay))).to be_empty
  end

  it "keeps a KCS Power frozen, with its I/O RAM" do
    kcs = pokes(cartridge(2), [[0xdf00, 0x5a], [0xdf7f, 0x33]]).tap(&:press_button).tap(&:freeze!)
    expect(state_differences(kcs, rebuilt(kcs))).to be_empty
  end

  it "keeps a GEO-RAM's RAM and registers" do
    geo = pokes(attach(described_class::GeoRAM.new(size: 64)), [[0xdfff, 2], [0xdffe, 5], [0xde10, 0x99]])
    expect(state_differences(geo, rebuilt(geo))).to be_empty
  end

  described_class::HARDWARE_TYPES.each do |type, mapper|
    it "keeps a #{mapper.name.split('::').last} as its registers leave it" do
      cart = pokes(cartridge(type), [0xde00, 0xde01, 0xde02, 0xdfff].map { |addr| [addr, 0x09] })
      cart.peek(0xde05) unless cart.readable_io_pages.empty?
      expect(state_differences(cart, rebuilt(cart))).to be_empty
    end
  end

  describe "in a machine", :slow do
    def restored(computer)
      state = computer.snapshot
      Badline::Computer.setup(state).build.restore(state)
    end

    def machine(cartridge) = run(Badline::Computer.new.tap { |computer| computer.attach_cartridge(cartridge) }, 10_001)

    it "builds the EasyFlash again in a machine without one" do
      computer = machine(cartridge(32, banks(2) + banks(2, address: 0xa000)))
      expect(state_differences(computer, restored(computer))).to be_empty
    end

    it "builds the GEO-RAM again, with its RAM, and runs on alike" do
      computer = machine(pokes(described_class::GeoRAM.new(size: 64), [[0xdfff, 1], [0xde20, 0x77]]))
      copy = restored(computer)
      expect(Badline::Checkpoint.take(run(copy, 10_000))).to eq(Badline::Checkpoint.take(run(computer, 10_000)))
    end
  end
end
