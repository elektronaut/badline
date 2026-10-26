# frozen_string_literal: true

require "spec_helper"
require "badline/plus4"

describe Badline::Drives::Model1551 do
  subject(:drive) { described_class.new(rom: stub_rom) }

  # A 16 KB stand-in for the DOS at $C000-$FFFF: NOPs, with the reset and
  # IRQ vectors pointing into drive RAM.
  let(:stub_rom) do
    bytes = Array.new(0x4000, 0xea)
    bytes[0x3ffc, 4] = [0x00, 0x03, 0x00, 0x04]
    Badline::ROM.new(bytes, length: 0x4000, start: 0xc000)
  end

  def run(cycles) = cycles.times { drive.cycle! }

  def load(bytes, at: 0x0300) = drive.ram.write(at, bytes)

  # The port driven as the DOS drives it: P0-P3, P5 and P6 out.
  def port(value)
    drive.bus.poke(0x00, 0x6f)
    drive.bus.poke(0x01, value)
  end

  describe "the bus" do
    it "reads the ROM's reset vector from $FFFC" do
      drive.cpu.step!
      expect(drive.cpu.program_counter).to eq(0x0300)
    end

    it "has 2 KB of RAM" do
      drive.bus.poke(0x07ff, 0x42)
      expect(drive.ram.peek(0x07ff)).to eq(0x42)
    end

    it "puts the CPU's port at $00 and $01" do
      drive.bus.poke(0x00, 0x6f)
      expect(drive.port.ddr).to eq(0x6f)
    end

    it "finds open bus at $0800-$3FFF" do
      drive.bus.peek(0xc123)
      expect(drive.bus.peek(0x0800)).to eq(0xea)
    end

    it "finds open bus at $8000-$BFFF" do
      drive.bus.peek(0xc123)
      expect(drive.bus.peek(0x8000)).to eq(0xea)
    end

    it "mirrors the TIA's registers through $4000-$7FFF" do
      drive.bus.poke(0x7ffb, 0x42)
      expect(drive.tia.directions[0]).to eq(0x42)
    end
  end

  describe "the 555" do
    it "interrupts the CPU every 16,660 cycles" do
      load([0x58, 0x4c, 0x01, 0x03]) # CLI; JMP *
      load([0xe6, 0x10, 0x40], at: 0x0400) # INC $10; RTI
      run((described_class::IRQ_PERIOD * 3) + 100)
      expect(drive.ram.peek(0x10)).to eq(3)
    end
  end

  describe "the port" do
    it "runs the motor with P2 high" do
      port(0x04)
      expect(drive.mechanism).to be_motor_on
    end

    it "lights the LED with P3 high" do
      port(0x08)
      expect(drive.led_on?).to be(true)
    end

    it "selects the speed zone with P5 and P6" do
      port(0x40)
      expect(drive.mechanism.zone).to eq(2)
    end

    it "steps the head with P0 and P1" do
      port(0x04)
      port(0x05)
      expect(drive.mechanism.half_track).to eq(37)
    end

    it "reads a writable disk's sensor high on P4" do
      drive.insert(Badline::Drives::Model1541::Disk.new)
      expect(drive.bus.peek(0x01) & 0x10).to eq(0x10)
    end

    it "reads a write-protected disk's sensor low on P4" do
      disk = Badline::Drives::Model1541::Disk.new
      allow(disk).to receive(:write_protected?).and_return(true)
      drive.insert(disk)
      expect(drive.bus.peek(0x01) & 0x10).to eq(0)
    end

    it "reads BYTE LATCHED on P7 once a byte has come off the disk" do
      drive.insert(Badline::Drives::Model1541::Disk.new)
      port(0x04)
      run(80)
      expect(drive.bus.peek(0x01) & 0x80).to eq(0x80)
    end

    it "reads BYTE LATCHED low again once the CPU reaches the TIA" do
      drive.insert(Badline::Drives::Model1541::Disk.new)
      port(0x04)
      run(80)
      drive.bus.peek(0x4000)
      expect(drive.bus.peek(0x01) & 0x80).to eq(0)
    end
  end

  describe "the TIA" do
    it "reads the byte the gate array latched on port B" do
      drive.mechanism.latched_byte = 0x52
      expect(drive.bus.peek(0x4001)).to eq(0x52)
    end

    it "reads SYNC high on PC6 outside a SYNC mark" do
      expect(drive.bus.peek(0x4002) & 0x40).to eq(0x40)
    end

    it "reads the jumper low on PC5 for device 8" do
      expect(drive.bus.peek(0x4002) & 0x20).to eq(0)
    end

    it "reads the jumper high on PC5 for device 9" do
      expect(described_class.new(rom: stub_rom, device: 9).bus.peek(0x4002) & 0x20).to eq(0x20)
    end

    it "puts the head in write mode with PC4 low" do
      drive.bus.poke(0x4005, 0x1f)
      drive.bus.poke(0x4002, 0x00)
      expect(drive.mechanism).to be_writing
    end

    it "keeps the head reading while PC4 is an input" do
      drive.bus.poke(0x4002, 0x00)
      expect(drive.mechanism).not_to be_writing
    end
  end

  it "refuses device numbers other than 8 and 9" do
    expect { described_class.new(rom: stub_rom, device: 10) }.to raise_error(ArgumentError)
  end

  it "resets the CPU to the reset vector" do
    load([0x4c, 0x00, 0x03]) # JMP *
    run(10)
    drive.reset!
    run(7)
    expect(drive.cpu.program_counter).to be_between(0x0300, 0x0303)
  end

  describe "with the DOS", :slow do
    subject(:drive) { described_class.new }

    it "comes to its idle loop" do
      1_200_000.times do
        drive.cycle!
        break if drive.cpu.program_counter == described_class::IDLE_LOOP
      end
      expect(drive.cpu.program_counter).to eq(described_class::IDLE_LOOP)
    end
  end
end
