# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require_relative "../../../support/blank_disk"
require_relative "../../../support/drive1541_rom"
require_relative "../../../support/keyed_oracle"

# A 1541's mechanism and disk through their keyed fields, against the
# positional state, which restores exactly: the drive reading a D64 with
# its motor on, then writing a run of bytes, saved now and then, its disk
# built again from the image the module embeds and the tracks it holds,
# and the mechanism loaded over it.
module Drive1541KeyedSamples
  extend BlankDisk
  extend KeyedOracle

  module_function

  def drive_with_disk
    drive = Badline::Drives::Model1541.new(rom: Drive1541ROM.stub)
    drive.insert(Badline::Drives::Model1541::Disk.open(blank_d64(File.join(Dir.mktmpdir, "blank.d64"))))
    drive.ram.write(0x0300, [0x4c, 0x00, 0x03])
    { 0x1c02 => 0x6f, 0x1c0c => 0xee, 0x1c0b => 0x01, 0x1c00 => 0x44 }.each { |reg, value| drive.via2.poke(reg, value) }
    drive
  end

  def check(drive)
    out = Badline::Snapshot::Keyed::Writer.new
    drive.disk.save_fields(out)
    drive.mechanism.save_fields(out)
    input = Badline::Snapshot::Keyed::Reader.parse(out.section("BL-D8-DISK"))
    mechanism = Badline::Drives::Model1541::Mechanism.new
    mechanism.load_fields(input, Badline::Drives::Model1541::Disk.from_fields(input))
    problems = input.report.lines(verbose: true)
    problems << "positional state differs" unless positional(mechanism) == positional(drive.mechanism)
    problems.map { |line| "cycle #{drive.cycles}: #{line}" }
  end

  def samples
    @samples ||= begin
      drive = drive_with_disk
      problems = []
      6_000.times do |cycle|
        drive.cycle!
        problems.concat(check(drive)) if (cycle % 197).zero?
      end
      drive.via2.poke(0x1c03, 0xff)
      drive.via2.poke(0x1c0c, 0xce)
      3_000.times do |cycle|
        drive.via2.poke(0x1c01, cycle & 0xff) if (cycle % 26).zero?
        drive.cycle!
        problems.concat(check(drive)) if (cycle % 149).zero?
      end
      problems
    end
  end
end

describe Badline::Drives::Model1541::KeyedState do
  it "restores the mechanism and the disk reading and writing" do
    expect(Drive1541KeyedSamples.samples.first(5)).to be_empty
  end

  context "with the drive's own fields and its RAM" do
    let(:drive) { Drive1541KeyedSamples.drive_with_disk.tap { |each| 5_003.times { each.cycle! } } }
    let(:fresh) { Badline::Drives::Model1541.new(rom: Drive1541ROM.stub) }

    before do
      out = Badline::Snapshot::Keyed::Writer.new
      drive.save_fields(out)
      drive.bus.save_fields(out)
      input = Badline::Snapshot::Keyed::Reader.parse(out.section("BL-D8"))
      fresh.load_fields(input)
      fresh.bus.load_fields(input)
    end

    it "restores the clock, the cycles, the serial latch and the RAM" do
      expect([fresh.cycles, Drive1541KeyedSamples.positional(fresh.bus)])
        .to eq([drive.cycles, Drive1541KeyedSamples.positional(drive.bus)])
    end
  end

  context "with a disk whose image file is gone" do
    let(:drive) { Drive1541KeyedSamples.drive_with_disk }
    let(:input) do
      out = Badline::Snapshot::Keyed::Writer.new
      drive.disk.save_fields(out)
      File.delete(drive.disk.path)
      Badline::Snapshot::Keyed::Reader.parse(out.section("BL-D8-DISK"))
    end

    it "keeps it write-protected" do
      expect(Badline::Drives::Model1541::Disk.from_fields(input)).to be_write_protected
    end
  end
end
