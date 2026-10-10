# frozen_string_literal: true

require "spec_helper"

describe Badline::Drive1571::WD1770 do
  subject(:fdc) { described_class.new.tap { |wd| wd.cpu = clock } }

  let(:clock) { Struct.new(:cycles).new(0) }

  def after(cycles)
    clock.cycles += cycles
    fdc.peek(0)
  end

  it "reads idle with no command" do
    expect(fdc.peek(0)).to eq(0)
  end

  it "goes busy as a sector read is written" do
    fdc.poke(0, 0x88)
    expect(fdc.peek(0) & described_class::BUSY).to eq(described_class::BUSY)
  end

  it "ends a sector read with record not found after five turns, finding no MFM sector" do
    fdc.poke(0, 0x88)
    expect([after((described_class::TURN * 5) - 1) & 0x01, after(1)]).to eq([1, described_class::NOT_FOUND])
  end

  it "restores to track 0, reporting it" do
    fdc.poke(1, 5)
    fdc.poke(0, 0x00)
    expect([fdc.peek(1), after(described_class::STEP * 5)]).to eq([0, described_class::TRACK0])
  end

  it "seeks to the track in the data register" do
    fdc.poke(3, 12)
    fdc.poke(0, 0x10)
    expect(fdc.peek(1)).to eq(12)
  end

  it "ends a command at once on a force interrupt" do
    fdc.poke(0, 0x88)
    fdc.poke(0, 0xd0)
    expect(fdc.peek(0) & described_class::BUSY).to eq(0)
  end

  it "loads a state holding the four registers alone" do
    out = Badline::Snapshot::StateWriter.new
    out.ints([1, 2, 3, 4])
    fdc.load_state(Badline::Snapshot::StateReader.new(out.state))
    expect([fdc.peek(1), fdc.peek(2), fdc.peek(3), fdc.peek(0)]).to eq([2, 3, 4, 0])
  end
end
