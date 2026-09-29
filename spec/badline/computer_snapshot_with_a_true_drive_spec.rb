# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require_relative "../support/blank_disk"
require_relative "../support/snapshot_scenarios"

# A C64 with a true 1541, saved while the drive loads a file for it.
describe Badline::Computer, "#snapshot with a true drive", :slow do
  include BlankDisk
  include SnapshotScenarios

  let(:idle) do
    { "Badline::Drive1541" => %i[@owed @budget @slept @wake_at @pass_cycles @pass_instructions @record_state
                                 @record_cycles @record_instructions @record_quiet @asleep @recording],
      "Badline::Drive1541::Bus" => %i[@touched @volatile @watching] }
  end
  let(:dir) { Dir.mktmpdir }
  let(:path) do
    File.join(dir, "demo.d64").tap do |disk|
      blank_d64(disk)
      Badline::Storage::D64Image.new(disk).write_file("DEMO", SnapshotScenarios::DEMO_PRG)
    end
  end
  # 3.5M cycles in, the drive's motor runs and the DOS reads the file's
  # sectors, at an odd cycle.
  let(:computer) do
    described_class.new.tap do |machine|
      Badline::Media::TrueDrive.plug(machine)
      Badline::Media.attach(machine, path)
      run(machine, 3_500_001)
    end
  end
  let(:target) { described_class.new }

  after { FileUtils.remove_entry(dir) }

  def drive_digest(machine)
    drive = machine.drive1541
    [drive.cycles, drive.cpu.program_counter, drive.cpu.a, drive.cpu.x, drive.cpu.y, drive.cpu.p,
     drive.ram.read(0, 0x800), drive.mechanism.half_track, drive.mechanism.motor_on?]
  end

  it "saves the drive mid-load" do
    expect(computer.drive1541.mechanism).to be_motor_on
  end

  it "restores the drive and its disk in a machine without one" do
    target.restore(computer.snapshot)
    expect(state_differences(computer, target, host: idle)).to be_empty
  end

  it "runs on as the saved machine does" do
    target.restore(computer.snapshot)
    digests = Array.new(4) do
      [computer, target].map { |machine| [Badline::Checkpoint.take(run(machine, 250_000)), drive_digest(machine)] }
    end
    expect(digests).to all(satisfy { |ours, theirs| ours == theirs })
  end
end
