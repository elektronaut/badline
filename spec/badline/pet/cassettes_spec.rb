# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

describe Badline::PET::Cassettes do
  let(:pet) { Badline::PET.new(model: "3032") }
  let(:cassettes) { pet.cassettes }

  # The editor's set-up of the VIA's port B, motor 2 off.
  before do
    pet.poke(0xe840, 0x1e)
    pet.poke(0xe842, 0x1e)
  end

  it "runs motor 1 while PIA 1's CB2 is low" do
    pet.poke(0xe813, 0x34)
    expect(cassettes.datasette1.motor?).to be(true)
  end

  it "stops motor 1 while PIA 1's CB2 is high" do
    pet.poke(0xe813, 0x34)
    pet.poke(0xe813, 0x3c)
    expect(cassettes.datasette1.motor?).to be(false)
  end

  it "runs while a deck's tape runs" do
    cassettes.datasette2.insert(instance_double(Badline::Storage::TAP, rewind: nil))
    cassettes.datasette2.play!
    pet.poke(0xe840, 0x0e)
    expect(cassettes.running?).to be(true)
  end

  it "runs motor 2 while the VIA's PB4 is low" do
    pet.poke(0xe840, 0x0e)
    expect([cassettes.datasette1.motor?, cassettes.datasette2.motor?]).to eq([false, true])
  end

  it "reads deck 1's keys on PIA 1's PA4" do
    pet.poke(0xe811, 0x04)
    cassettes.datasette1.play!
    expect(pet.peek(0xe810) & 0x30).to eq(0x20)
  end

  it "reads deck 2's keys on PIA 1's PA5" do
    pet.poke(0xe811, 0x04)
    cassettes.datasette2.play!
    expect(pet.peek(0xe810) & 0x30).to eq(0x10)
  end

  context "with a tape playing" do
    let(:dir) { Dir.mktmpdir }

    # A tape of one short pulse after another.
    def tape
      path = File.join(dir, "pulses.tap")
      File.binwrite(path, "C64-TAPE-RAW".b + [1, 3, 0, 0, 4, 0, 0, 0, 0x30, 0x30, 0x30, 0x30].pack("C*"))
      Badline::Storage::TAP.new(path)
    end

    after { FileUtils.remove_entry(dir) }

    it "flags deck 1's falling edges on PIA 1's CA1" do
      cassettes.datasette1.insert(tape)
      cassettes.datasette1.play!
      pet.poke(0xe813, 0x34)
      500.times { cassettes.cycle! }
      expect(pet.pia1.cra & 0x80).to eq(0x80)
    end

    it "flags deck 2's falling edges on the VIA's CB1" do
      cassettes.datasette2.insert(tape)
      cassettes.datasette2.play!
      pet.poke(0xe840, 0x0e)
      500.times { cassettes.cycle! }
      expect(pet.via.interrupt_flags & 0x10).to eq(0x10)
    end
  end
end
