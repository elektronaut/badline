# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require "badline/drives/model8050"
require_relative "../../../support/blank_disk"

# The drives as DOS 2.7's controller program (901869-01) drives them: its
# interrupt steps the heads ($FF9C) and turns the motors, and its read and
# write loops wait on byte ready ($FD9C, $FDD2).
describe Badline::Drives::Model8050::Mechanism do
  include BlankDisk

  subject(:mechanism) do
    described_class.new(sides:).tap do |drives|
      drives.via = via
      drives.rriot = rriot
    end
  end

  let(:sides) { 1 }
  let(:via) { Badline::Chips::VIA.new(start: 0x40) }
  let(:rriot) { Badline::Chips::RRIOT.new(rom: Array.new(0x400, 0)) }
  let(:dir) { Dir.mktmpdir }
  let(:disk) { Badline::Drives::Model8050::Disk.new(Badline::Storage::D80Image.new(blank_d80(path, id: "AB"))) }

  after { FileUtils.remove_entry(dir) }

  def path = File.join(dir, "blank.d80")

  def run(cycles) = cycles.times { mechanism.cycle! }

  # VIA port B as the controller drives it: PB0-PB6 out.
  def drives(value)
    via.poke(0x42, 0x7f)
    via.poke(0x40, value)
    mechanism.cycle!
  end

  # The 6530's port B: drive, zone and side out.
  def select(drive: 0, zone: 3, side: 0)
    rriot.poke(0x03, 0x17)
    rriot.poke(0x02, drive | (zone << 1) | (side.zero? ? 0x10 : 0x00))
  end

  # Drive 0's motor on, its phases as given.
  def spin(phase = 0) = drives(0x10 | (phase << 2))

  # Runs a cycle, returning whether byte ready pulsed.
  def tick
    mechanism.cycle!
    mechanism.take_so
  end

  # The bytes byte ready latches over the next +count+ pulses.
  def read_bytes(count)
    bytes = []
    while bytes.length < count
      bytes << mechanism.data_in if tick
    end
    bytes
  end

  def pulses_in(cycles) = Array.new(cycles) { tick }.count(true)

  # The cycles until byte ready has pulsed +count+ times.
  def cycles_for(count)
    cycles = 0
    pulses = 0
    until pulses == count
      cycles += 1
      pulses += 1 if tick
    end
    cycles
  end

  describe "the stepper" do
    it "moves drive 0's head a track in for each phase of 00, 01, 11, 10" do
      [0b01, 0b11, 0b10, 0b00, 0b01].each { |phase| drives(0x30 | (phase << 2)) }
      expect(mechanism.cylinders).to eq([5, 0])
    end

    it "moves it out through 00, 10, 11, 01, and stops it at track 1" do
      [0b01, 0b11, 0b11, 0b01, 0b00, 0b10].each { |phase| drives(0x30 | (phase << 2)) }
      expect(mechanism.cylinders).to eq([0, 0])
    end

    it "moves drive 1's head on PB0 and PB1" do
      [0b01, 0b11].each { |phase| drives(0x30 | phase) }
      expect(mechanism.cylinders).to eq([0, 2])
    end
  end

  describe "reading" do
    before do
      mechanism.insert(disk)
      select
      spin
    end

    it "latches the header after the syncs" do
      expect(read_bytes(7)).to eq([0x08, 1 ^ 0x41 ^ 0x42, 0, 1, 0x42, 0x41, 0x0f])
    end

    it "pulls SYNC low after a sync cell, with no byte ready" do
      run(4 * 22)
      expect([mechanism.sync?, mechanism.take_so]).to eq([true, false])
    end

    it "passes three zone 3 cells every 65 cycles" do
      read_bytes(1)
      expect(cycles_for(3)).to eq(65)
    end

    it "pulses byte ready for each data cell of a 200,000-cycle turn", :slow do
      expect(pulses_in(200_000)).to eq(9230 - (29 * 9))
    end

    it "shows no SYNC off the other drive, which has no disk" do
      run(4 * 22)
      select(drive: 1)
      expect(mechanism.sync?).to be(false)
    end

    it "turns no disk with the motor off" do
      drives(0x30)
      run(1000)
      expect(mechanism.take_so).to be(false)
    end

    it "passes three zone 0 cells every 80 cycles" do
      [0b01, 0b11, 0b10, 0b00].cycle.first(64).each { |phase| spin(phase) }
      select(zone: 0)
      read_bytes(1)
      expect(Array.new(80) { tick }.count(true)).to eq(3)
    end
  end

  describe "writing" do
    before do
      mechanism.insert(disk)
      select
      spin
      via.poke(0x4c, 0xdc)
      rriot.poke(0x01, 0xff)
      rriot.poke(0x00, 0x5a)
      read_bytes(3)
    end

    it "writes the 6530's port A into each cell" do
      expect(disk.track(1)[0, 3]).to eq([0x5a, 0x5a, 0x5a])
    end

    it "stores what it wrote once the motor stops" do
      allow(disk).to receive(:flush)
      drives(0x30)
      expect(disk).to have_received(:flush)
    end

    it "writes syncs while CA2 is high" do
      via.poke(0x4c, 0xde)
      read_bytes(2)
      expect(disk.track(1)[3, 2]).to all(eq(Badline::Drives::Model8050::Disk::SYNC))
    end
  end

  describe "the 6530's port B" do
    it "reads write protect high as a disk goes in" do
      mechanism.insert(disk)
      select
      expect(mechanism.status_lines & 0x08).to eq(0x08)
    end

    it "reads it low once the disk is in" do
      mechanism.insert(disk)
      select
      run(described_class::CHANGE_CYCLES)
      expect(mechanism.status_lines & 0x08).to eq(0)
    end

    it "reads it high for a write-protected disk" do
      image = Badline::Storage::D80Image.new(blank_d80(path), read_only: true)
      mechanism.insert(Badline::Drives::Model8050::Disk.new(image))
      select
      run(described_class::CHANGE_CYCLES)
      expect(mechanism.status_lines & 0x08).to eq(0x08)
    end

    context "with two sides" do
      let(:sides) { 2 }

      it "reads PB6 low" do
        select
        expect(mechanism.status_lines & 0x40).to eq(0)
      end
    end
  end
end
