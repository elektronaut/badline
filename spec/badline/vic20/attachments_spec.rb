# frozen_string_literal: true

require "spec_helper"
require "badline/vic20"
require "tmpdir"
require "fileutils"

describe Badline::Vic20::Attachments do
  subject(:machine) { Badline::Vic20.new }

  let(:layout) { Badline::KernalTrap::VIC20_LAYOUT }
  let(:dir) { Dir.mktmpdir }

  after { FileUtils.remove_entry(dir) }

  describe "#basic_start" do
    it "reads TXTTAB" do
      machine.ram.write(0x2b, [0x01, 0x12])
      expect(machine.basic_start).to eq(0x1201)
    end
  end

  describe "#attach_cartridge" do
    let(:chip) { Badline::Storage::CRTFile::Chip.new(chip_type: 0, bank: 0, address: 0xa000, data: [0x5a] * 0x100) }

    before do
      machine.run_cycles(100)
      machine.attach_cartridge([chip])
    end

    it "puts the chip's ROM in its block" do
      expect(machine.bus.peek(0xa080)).to eq(0x5a)
    end

    it "switches the machine off and on" do
      expect(machine.cpu.program_counter).to eq(0xfd22)
    end
  end

  # Calls LOAD for device 8 with no file name, which the trap answers
  # with the MISSING FILE NAME exit, and returns where the CPU went, a byte
  # on once it has fetched the opcode there.
  def load_without_a_name
    machine.ram.write(0xb7, [0x00, 0x00, 0x00, 0x08])
    machine.cpu.program_counter = layout.load
    machine.cpu.cycle!
    machine.cpu.program_counter
  end

  describe "#mount" do
    before { machine.mount(Badline::Storage::HostDirectory.new(dir)) }

    it { is_expected.to be_mounted }

    it "traps LOAD at the VIC-20's vector target" do
      expect(load_without_a_name).to eq(layout.missing_file_name_exit + 1)
    end
  end

  describe "#unmount" do
    before do
      machine.mount(Badline::Storage::HostDirectory.new(dir))
      allow(machine.cpu).to receive(:remove_trap).and_call_original
      machine.unmount
    end

    it { is_expected.not_to be_mounted }

    it "leaves LOAD to the ROM" do
      expect(load_without_a_name).to eq(layout.load + 1)
    end

    it "takes the serial traps out" do
      expect(machine.cpu).to have_received(:remove_trap).with(layout.talk)
    end
  end

  describe "#attach_drive1541" do
    let(:drive) { Badline::Drive1541.new }

    # Calls TALK for device 8 with a return address on the stack, and
    # returns where the CPU went: back to the caller when a trap answers.
    def talk_to_device8
      machine.ram.write(0x01fe, [0x33, 0x12])
      machine.cpu.stack_pointer = 0xfd
      machine.cpu.a = 8
      machine.cpu.program_counter = layout.talk
      machine.cpu.cycle!
      machine.cpu.program_counter
    end

    before do
      machine.mount(Badline::Storage::HostDirectory.new(dir))
      machine.attach_drive1541(drive)
    end

    it "puts the drive on the serial bus" do
      expect(machine.iec_bus.drives).to eq([drive])
    end

    it "waits for the drive to boot before the on_init handlers" do
      expect(machine.init_threshold).to eq(described_class::DRIVE_BOOT_CYCLES)
    end

    it "leaves device 8's serial traffic to the drive" do
      expect(talk_to_device8).to eq(layout.talk + 1)
    end

    it "gives device 8 back to the traps once the drive is unplugged" do
      machine.detach_drive1541
      expect(talk_to_device8).to eq(0x1235)
    end
  end

  context "when BASIC loads and saves through device 8" do
    let(:output) { machine.capture_output.output }

    before do
      File.binwrite(File.join(dir, "PROG.PRG"), [0x00, 0x1c, 0xa9, 0x2a].pack("C*"))
      machine.mount(Badline::Storage::HostDirectory.new(dir))
      machine.capture_output
      machine.on_init { machine.type_text(%(load"prog",8,1\rsave"copy",8\r)) }
      machine.run_cycles(machine.init_threshold + 300_000)
    end

    it "loads the file where it says, saves BASIC's program and prints the KERNAL's messages", :aggregate_failures do
      expect(machine.ram.read(0x1c00, 2)).to eq([0xa9, 0x2a])
      expect(File.binread(File.join(dir, "copy.prg")).bytes.first(2)).to eq([0x01, 0x10])
      expect(output).to include("searching for prog\nloading\nready.", "saving copy\nready.")
    end
  end
end
