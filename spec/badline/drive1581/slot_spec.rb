# frozen_string_literal: true

require "spec_helper"
require "badline/c128"
require_relative "../../support/snapshot_scenarios"

# A 1581 on each machine's serial bus.
describe Badline::Drive1581::Slot do
  include SnapshotScenarios

  # A 1581 whose ROM is NOPs, its reset vector in RAM.
  let(:drive) do
    bytes = Array.new(0x8000, 0xea)
    bytes[0x7ffc, 2] = [0x00, 0x03]
    Badline::Drive1581.new(rom: Badline::ROM.new(bytes, length: 0x8000, start: 0x8000))
  end

  context "with a C64" do
    let(:machine) { Badline::Computer.new }

    it "runs the drive at its own clock, two cycles a host cycle" do
      machine.attach_drive1581(drive)
      before = drive.cycles
      10.times { machine.cycle! }
      expect(drive.cycles - before).to be_between(20, 21)
    end

    it "makes the 1581 its true drive" do
      machine.attach_drive1581(drive)
      expect(machine.true_drive).to equal(drive)
    end

    it "takes the 1541's place on device 8" do
      Badline::Media::TrueDrive.plug(machine)
      machine.plug_drive1581
      expect(machine.drive1541).to be_nil
    end

    it "gives device 8 back to the 1541" do
      machine.plug_drive1581
      machine.plug_true_drive
      expect(machine.drive1581).to be_nil
    end

    it "resets it with the machine" do
      machine.attach_drive1581(drive)
      drive.cpu.program_counter = 0x0400
      machine.reset!
      expect(drive.cpu.program_counter).to eq(0x0300)
    end

    it "carries it through a snapshot" do
      machine.attach_drive1581(drive)
      machine.run_cycles(1_000)
      target = Badline::Computer.new
      target.restore(machine.snapshot)
      expect(target.drive1581.cycles).to eq(drive.cycles)
    end
  end

  context "with a VIC-20" do
    let(:machine) { Badline::Vic20.new }

    it "makes the 1581 its true drive" do
      machine.attach_drive1581(drive)
      expect(machine.true_drive).to equal(drive)
    end

    it "waits for its DOS to boot before typing" do
      machine.attach_drive1581(drive)
      expect(machine.init_threshold).to eq(Badline::Drive1581::BOOT_CYCLES)
    end
  end

  context "with a C128" do
    let(:machine) { Badline::C128.new(mode: :c128) }

    it "makes the 1581 its true drive ahead of the 1571" do
      machine.attach_drive1571(Badline::Drive1571.new)
      machine.attach_drive1581(drive)
      expect(machine.true_drive).to equal(drive)
    end

    it "waits for its DOS to boot before typing" do
      machine.attach_drive1581(drive)
      expect(machine.init_threshold).to eq(Badline::Drive1581::BOOT_CYCLES)
    end

    it "runs the drive while the Z80 has the bus" do
      machine.attach_drive1581(drive)
      before = drive.cycles
      100.times { machine.cycle! }
      expect([machine.address_bus.z80?, drive.cycles - before]).to match([true, be_between(200, 203)])
    end

    it "finds it answering in burst mode", :slow do
      machine.attach_drive1581(Badline::Drive1581.new)
      machine.on_init { machine.type_text("open1,8,15:close1\r") }
      machine.run_cycles(3_500_000)
      expect(machine.ram.peek(0x0a1c) & 0x40).to eq(0x40)
    end
  end
end
