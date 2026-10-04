# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require_relative "../support/blank_disk"
require_relative "../support/booted_machine"
require_relative "../support/snapshot_scenarios"

# Snapshots opened after the files of the media they were taken with are
# deleted.
describe Badline::Snapshot, ".load without the media files", :slow do
  include BlankDisk
  include BootedMachine
  include SnapshotScenarios

  let(:dir) { Dir.mktmpdir }
  let(:program) { SnapshotScenarios::DEMO_PRG }

  after { FileUtils.remove_entry(dir) }

  def reloaded(machine, media)
    path = File.join(dir, "machine.vsf")
    described_class.save(machine, path)
    File.delete(media)
    described_class.load(path)
  end

  def digests(machine, &)
    Array.new(2) do
      run(machine, 200_000)
      [Badline::Checkpoint.take(machine), *yield(machine)]
    end
  end

  describe "with a tape playing" do
    let(:tape) do
      pulses = Array.new(10_000) { |i| 0x20 + ((i * 37) % 0x40) }
      File.join(dir, "noise.tap").tap do |file|
        File.binwrite(file, "C64-TAPE-RAW".b + [1, 0, 0, 0, pulses.length].pack("C4V") + pulses.pack("C*"))
      end
    end
    let(:machine) do
      booted.tap do |computer|
        Badline::Media.attach(computer, tape)
        run(computer, 200_001)
      end
    end

    def tape_digest(computer) = [computer.datasette.tape.position, computer.datasette.motor?]

    it "plays the tape on from the snapshot" do
      restored = reloaded(machine, tape)
      expect(digests(restored) { |computer| tape_digest(computer) })
        .to eq(digests(machine) { |computer| tape_digest(computer) })
    end
  end

  describe "with a .t64 served as device 8" do
    let(:archive) do
      entry = [1, 0x82, 0x01, 0x08, program.length - 1, 0x08, 0, 0, 0x60, 0, 0, 0, 0, 0, 0, 0]
      header = "C64S tape image file".ljust(0x20, "\0").b + [0x0100, 1, 1, 0].pack("vvvv") + "DEMO".ljust(24)
      File.join(dir, "demo.t64").tap do |file|
        File.binwrite(file, header + entry.pack("C*") + "DEMO".ljust(16) + program.drop(2).pack("C*"))
      end
    end
    let(:machine) { booted.tap { |computer| computer.mount(Badline::Storage::T64.new(archive)) } }

    def loading(computer)
      computer.type_text(%(load"demo",8\r))
      computer
    end

    def loaded(computer) = [computer.ram.read(0x0801, program.length - 2)]

    it "loads from the archive as the saved machine does" do
      restored = loading(reloaded(machine, archive))
      expect(digests(restored) { |computer| loaded(computer) })
        .to eq(digests(loading(machine)) { |computer| loaded(computer) })
    end

    it "loads the program" do
      restored = run(loading(reloaded(machine, archive)), 200_000)
      expect(loaded(restored)).to eq([program.drop(2)])
    end
  end

  describe "with a .g64 in a true 1541" do
    let(:image) do
      d64 = File.join(dir, "demo.d64")
      blank_d64(d64)
      Badline::Storage::D64Image.new(d64).write_file("DEMO", program)
      disk = Badline::Drive1541::Disk.open(d64)
      tracks = (2..Badline::Drive1541::Disk::MAX_HALF_TRACK).filter_map do |half|
        [half - 2, [disk.track(half).bytes, disk.track(half).zone]] if disk.track(half)
      end
      File.join(dir, "demo.g64").tap { |file| Badline::Storage::G64Image.create(file, tracks.to_h) }
    end
    # 300K cycles after LOAD is typed, the drive's motor runs and the DOS
    # reads the directory.
    let(:machine) do
      booted.tap do |computer|
        Badline::Media.attach(computer, image)
        run(computer, 300_001)
      end
    end

    def drive_digest(computer)
      drive = computer.drive1541
      [drive.cycles, drive.cpu.program_counter, drive.ram.read(0, 0x800), drive.mechanism.half_track,
       drive.mechanism.motor_on?]
    end

    it "loads on as the saved machine does" do
      restored = reloaded(machine, image)
      expect(digests(restored) { |computer| drive_digest(computer) })
        .to eq(digests(machine) { |computer| drive_digest(computer) })
    end
  end
end
