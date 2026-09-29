# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require_relative "../support/blank_disk"
require_relative "../support/snapshot_scenarios"

describe Badline::Drive1541, "#save_state" do
  include BlankDisk
  include SnapshotScenarios

  # What Idle keeps about the pass it records or sleeps through, which a
  # saved drive settles and a restored one starts without.
  let(:idle) do
    { "Badline::Drive1541" => %i[@owed @budget @slept @wake_at @pass_cycles @pass_instructions @record_state
                                 @record_cycles @record_instructions @record_quiet @asleep @recording],
      "Badline::Drive1541::Bus" => %i[@touched @volatile @watching] }
  end
  let(:dir) { Dir.mktmpdir }
  let(:path) { File.join(dir, "disk.d64").tap { |disk| blank_d64(disk) } }
  # The DOS's power-up tests, with the motor on and the disk turning
  # under the head, at an odd cycle.
  let(:drive) { described_class.new.tap { |drive| drive.insert(Badline::Drive1541::Disk.open(path)) } }
  let(:target) { described_class.new }

  before { 20_001.times { drive.cycle! } }

  after { FileUtils.remove_entry(dir) }

  it "saves a drive with the motor on" do
    expect(drive.mechanism).to be_motor_on
  end

  it "restores the drive as it was" do
    expect(state_differences(drive, round_trip(drive, target), host: idle)).to be_empty
  end

  it "runs on as the saved drive does" do
    round_trip(drive, target)
    50_000.times { [drive, target].each(&:cycle!) }
    expect(state_differences(drive, target, host: idle)).to be_empty
  end

  it "keeps the disk in a drive that has the same image in" do
    disk = Badline::Drive1541::Disk.open(path)
    target.insert(disk)
    expect(round_trip(drive, target).disk).to equal(disk)
  end

  it "opens the image for a drive without it" do
    expect(round_trip(drive, target).disk.path).to eq(File.expand_path(path))
  end

  it "takes the disk out of a drive when the saved one had none" do
    target.insert(Badline::Drive1541::Disk.open(path))
    expect(round_trip(described_class.new, target).disk).to be_nil
  end

  it "keeps which tracks the head wrote and hasn't flushed" do
    drive.disk.written(36)
    expect(round_trip(drive, target).disk).to be_written
  end
end
