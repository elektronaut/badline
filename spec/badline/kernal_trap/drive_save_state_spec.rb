# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require_relative "../../support/blank_disk"
require_relative "../../support/snapshot_scenarios"

describe Badline::KernalTrap::Drive, "#save_state" do
  include BlankDisk
  include SnapshotScenarios

  # Storage keeps its directory listing as it reads it.
  let(:caches) do
    { "Badline::Storage::D64Image" => %i[@entries], "Badline::Storage::T64" => %i[@entries] }
  end
  let(:dir) { Dir.mktmpdir }
  let(:program) { [0x01, 0x08, 0xa9, 0x00, 0x60] }
  let(:d64) do
    Badline::Storage::D64Image.new(blank_d64(File.join(dir, "disk.d64"))).tap do |image|
      image.write_file("prog", program, type: :prg)
    end
  end

  def reopened(drive)
    out = Badline::Snapshot::StateWriter.new
    drive.save_state(out)
    input = Badline::Snapshot::StateReader.new(out.state)
    described_class.new(Badline::Storage.reopen(input)).tap do |copy|
      copy.load_state(input)
      raise "state left unread" unless input.finished?
    end
  end

  context "with a disk image" do
    let(:drive) do
      described_class.new(d64).tap do |drive|
        drive.open(2, "PROG")
        drive.read(2)
        drive.open(3, "#")
        drive.write(3, [1, 2, 3])
        drive.open(4, "NEW,S,W")
        drive.write(4, [0x41, 0x42])
        drive.open(15, "M-R\x00\x03\x02")
      end
    end

    it "comes back with its channels, status and RAM" do
      expect(state_differences(drive, reopened(drive), host: caches)).to be_empty
    end

    it "reopens the image with what was written to it" do
      drive.close(4)
      storage = reopened(drive).instance_variable_get(:@storage)
      expect(storage.read_file("new", type: :seq)).to eq([0x41, 0x42])
    end
  end

  it "reopens a host directory by its path" do
    File.binwrite(File.join(dir, "demo.prg"), program.pack("C*"))
    drive = described_class.new(Badline::Storage::HostDirectory.new(dir)).tap { |d| d.open(2, "DEMO") }
    expect(state_differences(drive, reopened(drive))).to be_empty
  end

  describe "with the traps of a machine" do
    let(:traps) { %i[@drive @serial_trap @save_trap] }

    # A machine with a SAVE and a LISTEN under way, and one restored from
    # its traps' state.
    def machines(storage)
      computer = Badline::Computer.new.tap { |machine| machine.mount(storage) }
      serial = computer.instance_variable_get(:@serial_trap)
      { :@listening => true, :@listen_channel => 2, :@buffer => [0x50, 0x52] }
        .each { |name, value| serial.instance_variable_set(name, value) }
      computer.instance_variable_get(:@save_trap).instance_variable_set(:@saving, true)
      out = Badline::Snapshot::StateWriter.new
      computer.send(:save_trap_drive, out)
      target = Badline::Computer.new
      target.send(:load_trap_drive, Badline::Snapshot::StateReader.new(out.state))
      [computer, target]
    end

    it "mounts the storage again, with the serial and SAVE traps' state" do
      computer, target = machines(d64)
      differences = traps.flat_map do |name|
        state_differences(computer.instance_variable_get(name), target.instance_variable_get(name), host: caches)
      end
      expect(differences).to be_empty
    end
  end
end
