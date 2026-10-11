# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "badline/c128"
require_relative "../../../support/blank_disk"

# A 1571 through its keyed modules (Model1571#save_modules): its own
# fields, RAM, VIAs, CIA, CPU, WD1770, mechanism and disk, loaded into a
# fresh drive, which saves the same modules again.
module Drive1571KeyedSamples
  extend BlankDisk

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

  # The drive's modules (Model1571#save_modules), loaded into a fresh
  # drive, and the readers.
  def copy(drive)
    modules = Badline::Snapshot::Keyed::Modules.new(drive.save_modules([], "BL-D8"))
    fresh = Badline::Drives::Model1571.new(rom: stub_rom)
    fresh.load_modules(modules, modules.required("BL-D8"), "BL-D8")
    [fresh, modules.readers]
  end

  def samples
    @samples ||= begin
      saved = drive
      Array.new(6_000) do |cycle|
        saved.cycle!
        next [] unless (cycle % 211).zero?

        fresh, inputs = copy(saved)
        problems = inputs.flat_map { |input| input.report.lines(verbose: true) }
        problems << "saves other modules" unless fresh.save_modules([], "BL-D8") == saved.save_modules([], "BL-D8")
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
