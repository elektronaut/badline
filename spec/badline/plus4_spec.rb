# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "badline/plus4"
require_relative "../support/booting"

describe Badline::Plus4 do
  include Booting

  # The 25 rows of 40 characters on the screen at $0C00, as text.
  def screen(machine)
    Array.new(25) do |row|
      Array.new(40) { |col| character(machine.ram.peek(0x0c00 + (row * 40) + col)) }.join.rstrip
    end
  end

  def character(code)
    code &= 0x7f
    code.between?(1, 26) ? (code + 64).chr : code.chr
  end

  def booted(**) = boot(described_class.new(**))

  # Holds +key+ down for three frames, then up for three.
  def tap_key(machine, key)
    machine.keyboard.press(key)
    machine.run_cycles(57 * 312 * 3)
    machine.keyboard.release(key)
    machine.run_cycles(57 * 312 * 3)
  end

  it "starts at the KERNAL's reset entry" do
    expect(described_class.new.cpu.program_counter).to eq(0xfff6)
  end

  it "refuses a RAM size it can't fit" do
    expect { described_class.new(ram: 48) }.to raise_error(ArgumentError, /48K/)
  end

  it "names its model and RAM" do
    expect(described_class.new(model: "c16ntsc", ram: 32).model_label).to eq("C16 NTSC, 32K RAM")
  end

  it "takes its cartridges out and power cycles" do
    machine = described_class.new
    machine.attach_cartridge([Badline::Storage::CRTFile::Chip.new(0, 0, 0x8000, [0x11])])
    machine.run_cycles(10)
    machine.detach_cartridges
    expect([machine.cartridge_slots, machine.cycles, machine.cpu.program_counter]).to eq([[], 10, 0xfff6])
  end

  it "takes c116 for the C16" do
    expect(described_class.new(model: "c116").model).to eq(described_class::Model::C16)
  end

  {
    "plus4" => [nil, ["COMMODORE BASIC V3.5 60671 BYTES FREE", "3-PLUS-1 ON KEY F1", "", "READY."]],
    "plus4ntsc" => [nil, ["COMMODORE BASIC V3.5 60671 BYTES FREE", "3-PLUS-1 ON KEY F1", "", "READY."]],
    "c16" => [nil, ["COMMODORE BASIC V3.5 12277 BYTES FREE", "", "READY."]],
    "c16ntsc" => [nil, ["COMMODORE BASIC V3.5 12277 BYTES FREE", "", "READY."]],
    "c116" => [32, ["COMMODORE BASIC V3.5 28661 BYTES FREE", "", "READY."]]
  }.each do |model, (ram, lines)|
    it "boots the #{model}#{" with #{ram}K" if ram} to READY by its init threshold" do
      expect(screen(booted(model:, ram:)).map(&:strip).drop(1).first(lines.length)).to eq(lines)
    end
  end

  it "runs a line typed after boot" do
    machine = described_class.new(model: "c16")
    machine.type_text("print 6*7\r")
    boot(machine, past: 100_000)
    expect(screen(machine)[4, 3]).to eq(["PRINT 6*7", " 42", ""])
  end

  # The jiffy clock counts sixtieths of a second, so the PAL KERNAL counts
  # six jiffies every five frames.
  it "runs the KERNAL's jiffy clock off the raster interrupt" do
    machine = booted(model: "c16")
    before = machine.ram.peek(0xa5)
    machine.run_cycles(57 * 312 * 10)
    expect((machine.ram.peek(0xa5) - before) & 0xff).to eq(12)
  end

  describe "a directory mounted as device 8" do
    # 10 PRINT 6
    let(:program) { [0x01, 0x10, 0x09, 0x10, 0x0a, 0x00, 0x99, 0x20, 0x36, 0x00, 0x00, 0x00] }
    let(:machine) { described_class.new(model: "c16") }

    before do
      Dir.mktmpdir do |dir|
        File.binwrite(File.join(dir, "six.prg"), program.pack("C*"))
        machine.mount(Badline::Storage::HostDirectory.new(dir))
        machine.type_text(%(load"six",8\rrun\r))
        boot(machine, past: 300_000)
      end
    end

    it "loads a program through the KERNAL traps" do
      expect(screen(machine)).to include(" 6")
    end
  end

  describe "#attach_drive1541" do
    let(:machine) { described_class.new }
    let(:drive) { Badline::Drives::Model1541.new }

    # Calls TALK for device 8 with a return address on the stack, and
    # returns where the CPU went: back to the caller when a trap answers.
    def talk_to_device8
      machine.ram.write(0x01fe, [0x33, 0x12])
      machine.cpu.stack_pointer = 0xfd
      machine.cpu.a = 8
      machine.cpu.program_counter = Badline::KernalTrap::PLUS4_LAYOUT.talk
      machine.cpu.cycle!
      machine.cpu.program_counter
    end

    before do
      machine.mount(Badline::Storage::HostDirectory.new(Dir.tmpdir))
      machine.attach_drive1541(drive)
    end

    it "puts the drive on the serial bus" do
      expect(machine.iec_bus.drives).to eq([drive])
    end

    it "waits for the drive to boot before the on_init handlers" do
      expect(machine.init_threshold).to eq(described_class::DRIVE_BOOT_CYCLES)
    end

    it "leaves device 8's serial traffic to the drive" do
      expect(talk_to_device8).to eq(Badline::KernalTrap::PLUS4_LAYOUT.talk + 1)
    end

    it "gives device 8 back to the traps once the drive is unplugged" do
      machine.detach_drive1541
      expect(talk_to_device8).to eq(0x1235)
    end

    # TALK and LISTEN try a 1551's TCBM interface for devices 8 and 9
    # before the serial bus, and the traps answer device 8 ahead of that.
    context "with a 1551's TCBM interface plugged in" do
      let(:machine) { described_class.new(tcbm: true) }

      it "answers device 8 from the traps before the KERNAL probes it" do
        machine.detach_drive1541
        expect(talk_to_device8).to eq(0x1235)
      end
    end

    it "lets the drive see ATN as the port pulls it" do
      machine.poke(0x00, 0x07)
      machine.poke(0x01, 0x04)
      expect(drive.serial_bus.atn_low?).to be(true)
    end
  end

  describe "#attach_drive1551" do
    let(:machine) { described_class.new }
    let(:drive) { Badline::Drives::Model1551.new }

    before { machine.attach_drive1551(drive) }

    it "puts the drive's interface TIA at $FEE0 for device 8" do
      machine.poke(0xfef3, 0xff)
      machine.poke(0xfef0, 0x55)
      expect(drive.host_tia.ports[0]).to eq(0x55)
    end

    it "puts device 9's at $FEC0" do
      nine = Badline::Drives::Model1551.new(device: 9)
      machine.attach_drive1551(nine)
      machine.poke(0xfec3, 0xff)
      machine.poke(0xfec0, 0x66)
      expect(nine.host_tia.ports[0]).to eq(0x66)
    end

    it "waits for the drive to boot before the on_init handlers" do
      expect(machine.init_threshold).to eq(Badline::Drives::Model1551::BOOT_CYCLES)
    end

    it "is the true drive" do
      expect(machine.true_drive).to be(drive)
    end

    it "leaves $FEE0-$FEFF open once the drive is unplugged" do
      machine.detach_drive1551
      machine.poke(0x0002, 0x66)
      expect(machine.peek(0xfef0)).to eq(0x66)
    end

    context "with a TCBM interface of its own" do
      let(:machine) { described_class.new(tcbm: true) }

      it "gives the interface's TIA its place back once the drive is unplugged" do
        machine.detach_drive1551
        machine.poke(0xfef3, 0xff)
        machine.poke(0xfef0, 0x55)
        expect(machine.tias[0].ports[0]).to eq(0x55)
      end
    end

    it "resets the drive with the machine" do
      drive.tia.poke(0x4005, 0x1f)
      machine.reset!
      expect(drive.tia.directions[2]).to eq(0)
    end
  end

  describe "#plug_true_drive" do
    it "plugs in a 1551 by default" do
      expect(described_class.new.plug_true_drive.model_name).to eq("1551")
    end

    it "plugs in a 1551 by default on a C16" do
      expect(described_class.new(model: "c16").plug_true_drive.model_name).to eq("1551")
    end

    it "plugs in the 1541 true_drive_model names" do
      expect(described_class.new(true_drive_model: "1541").plug_true_drive.model_name).to eq("1541")
    end

    it "refuses a drive the Plus/4 doesn't take" do
      expect { described_class.new(true_drive_model: "1571") }.to raise_error(ArgumentError)
    end

    it "takes a 1551 out for a 1581 on device 8" do
      machine = described_class.new(true_drive_model: "1551")
      machine.plug_true_drive
      machine.plug_drive1581
      expect(machine.drive1551).to be_nil
    end
  end

  it "waits for a 1581 to boot before the on_init handlers" do
    machine = described_class.new
    machine.attach_drive1581(Badline::Drives::Model1581.new)
    expect(machine.init_threshold).to eq(Badline::Drives::Model1581::BOOT_CYCLES)
  end

  it "captures what the KERNAL prints" do
    machine = described_class.new(model: "c16")
    capture = machine.capture_output
    machine.type_text("print 6*7\r")
    boot(machine, past: 100_000)
    expect(capture.output).to include("42")
  end

  it "reads a held key through the keyboard latch" do
    machine = booted(model: "c16")
    machine.keyboard.press(:a)
    machine.run_cycles(57 * 312 * 4)
    expect(screen(machine)[4]).to eq("A")
  end

  it "starts 3-plus-1 in the function ROMs from F1 and RETURN at READY", :slow do
    machine = booted
    %i[f1 return].each { |key| tap_key(machine, key) }
    machine.run_cycles(60_000)
    expect([machine.bus.low_bank, machine.bus.high_bank]).to eq([1, 1])
  end

  it "reads joystick 2 through the keyboard latch" do
    machine = described_class.new
    machine.joystick2.press(:left)
    machine.poke(0xfd30, 0xff)
    machine.poke(0xff08, 0xfd)
    expect(machine.peek(0xff08)).to eq(0xfb)
  end

  it "shows the TED's picture" do
    machine = described_class.new
    expect(machine.video).to be(machine.ted)
  end

  it "runs frames of 57 cycles by 312 lines at the TED's PAL clock" do
    timing = described_class.new(model: "c16").timing
    expect([timing.clock_hz, timing.cycles_per_line, timing.lines_per_frame]).to eq([886_724, 57, 312])
  end

  it "crops xplus4's view on PAL, from the top border at the frame's end" do
    expect(described_class.new.timing.crop).to eq([0, 276, 384, 288])
  end

  it "runs frames of 262 lines and crops xplus4's view on NTSC" do
    timing = described_class.new(model: "plus4ntsc").timing
    expect([timing.clock_hz, timing.lines_per_frame, timing.crop]).to eq([894_886, 262, [0, 248, 384, 242]])
  end
end
