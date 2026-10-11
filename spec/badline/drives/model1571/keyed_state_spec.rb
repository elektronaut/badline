# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "badline/c128"
require_relative "../../../support/blank_disk"
require_relative "../../../support/keyed_oracle"
require_relative "../../../support/snapshot_scenarios"

# A 1571's own fields, its WD1770, RAM, CIA, mechanism and disk through
# their keyed fields, with its CPU and VIAs copied positionally (their keyed
# fields have oracles of their own), against the whole drive's positional
# state.
module Drive1571KeyedSamples
  extend BlankDisk
  extend KeyedOracle
  extend SnapshotScenarios

  module_function

  def stub_rom
    bytes = Array.new(0x8000, 0xea)
    bytes[0x7ffc, 4] = [0x00, 0x03, 0x00, 0x04]
    Badline::ROM.new(bytes, length: 0x8000, start: 0x8000)
  end

  def drive
    Badline::Drives::Model1571.new(rom: stub_rom).tap do |drive|
      drive.insert(Badline::Drives::Model1541::Disk.open(blank_d64(File.join(Dir.mktmpdir, "blank.d64"))))
      drive.ram.write(0x0300, [0xee, 0x00, 0x02, 0x4c, 0x00, 0x03])
      { 0x1803 => 0x66, 0x1801 => 0x20 }.each { |reg, value| drive.via1.poke(reg, value) }
      { 0x1c02 => 0x6f, 0x1c0c => 0xee, 0x1c00 => 0x44 }.each { |reg, value| drive.via2.poke(reg, value) }
      drive.bus.poke(0x2000, 0x80)
    end
  end

  # Each unit through a module of its own, as a snapshot keeps them.
  def through_module(unit)
    out = Badline::Snapshot::Keyed::Writer.new
    unit.save_fields(out)
    Badline::Snapshot::Keyed::Reader.parse(out.section("BL-TEST"))
  end

  def copy(drive)
    fresh = Badline::Drives::Model1571.new(rom: stub_rom)
    inputs = [drive, drive.bus, drive.cia].zip([fresh, fresh.bus, fresh.cia]).map do |unit, target|
      through_module(unit).tap { |input| target.load_fields(input) }
    end
    %i[via1 via2 cpu].each { |part| round_trip(drive.public_send(part), fresh.public_send(part)) }
    inputs << through_module(drive.fdc).tap { |input| fresh.fdc.load_fields(input) }
    out = Badline::Snapshot::Keyed::Writer.new
    drive.disk.save_fields(out)
    disk = Badline::Snapshot::Keyed::Reader.parse(out.section("BL-D8-DISK"))
    inputs << disk << through_module(drive.mechanism)
    fresh.mechanism.load_fields(inputs.last, Badline::Drives::Model1541::Disk.from_fields(disk))
    [fresh.cia, fresh].each(&:restored!)
    [fresh, inputs]
  end

  def samples
    @samples ||= begin
      saved = drive
      Array.new(6_000) do |cycle|
        saved.cycle!
        next [] unless (cycle % 211).zero?

        fresh, inputs = copy(saved)
        problems = inputs.flat_map { |input| input.report.lines(verbose: true) }
        problems << "positional state differs" unless positional(fresh) == positional(saved)
        problems.map { |line| "cycle #{cycle}: #{line}" }
      end.flatten
    end
  end
end

describe Badline::Drives::Model1571::KeyedState do
  it "restores the drive with its motor on, the WD1770 seeking" do
    expect(Drive1571KeyedSamples.samples.first(5)).to be_empty
  end
end
