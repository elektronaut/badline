# frozen_string_literal: true

require "spec_helper"
require "badline/plus4"
require_relative "../../../support/keyed_oracle"

describe Badline::Chips::ACIA::KeyedState do
  include KeyedOracle

  let(:clock_class) do
    Struct.new(:cycles, :irq, :due) do
      def acia_changed(irq, due)
        self.irq = irq
        self.due = due
      end
    end
  end
  let(:clock) { clock_class.new(0, false, nil) }

  def acia = Badline::Chips::ACIA.new(clock, 886_724)

  # An ACIA sending one byte at 300 baud with another waiting, its
  # transmitter's interrupt raised.
  def sending
    acia.tap do |sending|
      sending.poke(0xfd03, 0x16)
      sending.poke(0xfd02, 0x05)
      sending.poke(0xfd00, 0x41)
      sending.run!(29_557)
      sending.poke(0xfd00, 0x42)
    end
  end

  it "loads the command and control registers" do
    saved = acia.tap { |unit| unit.poke(0xfd03, 0x1e) }
    keyed_round_trip(saved, target = acia)
    expect([target.command, target.control]).to eq([0x00, 0x1e])
  end

  it "saves again what it loaded, mid-character" do
    saved = sending
    keyed_round_trip(saved, target = acia)
    expect(saved_fields(target)).to eq(saved_fields(saved))
  end

  it "runs on to the character's end it saved" do
    keyed_round_trip(sending, target = acia)
    expect(target.due).to eq(59_114)
  end

  it "starts the character clock of a snapshot that has none" do
    out = Badline::Snapshot::Keyed::Writer.new.int("command", 0x05).int("control", 0x16)
    clock.cycles = 1_000
    acia.tap { |target| target.load_fields(Badline::Snapshot::Keyed::Reader.parse(out.section("BL-ACIA"))) }.restored!
    expect(clock.due).to eq(30_557)
  end
end
