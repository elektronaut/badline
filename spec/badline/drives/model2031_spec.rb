# frozen_string_literal: true

require "spec_helper"
require "badline/drives/model2031"
require_relative "../../support/taken_once"

describe Badline::Drives::Model2031 do
  subject(:drive) { described_class.new(rom: stub_rom) }

  let(:ieee) { Badline::Drives::IEEEBus }

  # A 16 KB stand-in for the DOS at $C000-$FFFF: NOPs, with the reset and
  # IRQ vectors pointing into drive RAM.
  let(:stub_rom) do
    bytes = Array.new(0x4000, 0xea)
    bytes[0x3ffc, 4] = [0x00, 0x03, 0x00, 0x04]
    Badline::ROM.new(bytes, length: 0x4000, start: 0xc000)
  end

  def run(cycles) = cycles.times { drive.host_cycle! }

  # VIA 1's port B as the DOS sets it up to listen: PB0-PB2 and PB4 out.
  def listen(value)
    drive.bus.poke(0x1802, 0x17)
    drive.bus.poke(0x1800, value)
  end

  # VIA 1 as the DOS sets it up to talk: PB0, PB3, PB4 and PB6 out, and
  # port A out.
  def talk(port_b, port_a = 0xff)
    drive.bus.poke(0x1803, 0xff)
    drive.bus.poke(0x1801, port_a)
    drive.bus.poke(0x1802, 0x59)
    drive.bus.poke(0x1800, port_b)
  end

  # The controller pulls +lines+ low, and the drive takes them on its next
  # host cycle.
  def pull(lines)
    drive.ieee_bus.host_lines = lines
    run(1)
  end

  def low_lines = drive.ieee_bus.low_lines(drive.ieee_bus.host_lines)

  it "reads the ROM's reset vector from $FFFC" do
    expect(drive.cpu.program_counter).to eq(0x0300)
  end

  it "refuses device numbers other than 8 to 11" do
    expect { described_class.new(rom: stub_rom, device: 12) }.to raise_error(ArgumentError)
  end

  describe "ATN" do
    it "reads high on PB7 while the controller pulls ATN" do
      pull(ieee::ATN)
      expect(drive.bus.peek(0x1800) & 0x80).to eq(0x80)
    end

    it "reads low on PB7 while ATN is released" do
      expect(drive.bus.peek(0x1800) & 0x80).to eq(0)
    end

    it "flags CA1 on a rising edge, as the DOS sets it up" do
      drive.bus.poke(0x180c, 0x01)
      pull(ieee::ATN)
      run(1)
      expect(drive.via1.interrupt_flags & 0x02).to eq(0x02)
    end

    it "pulls NRFD and NDAC until the DOS acknowledges it" do
      listen(0x06)
      pull(ieee::ATN)
      expect(low_lines & (ieee::NRFD | ieee::NDAC)).to eq(ieee::NRFD | ieee::NDAC)
    end

    it "lets go of NRFD and NDAC once the DOS acknowledges it on PB0" do
      listen(0x07)
      pull(ieee::ATN)
      expect(low_lines & (ieee::NRFD | ieee::NDAC)).to eq(0)
    end

    it "pulls NRFD and NDAC while PB0 still acknowledges a released ATN" do
      listen(0x07)
      expect(low_lines & (ieee::NRFD | ieee::NDAC)).to eq(ieee::NRFD | ieee::NDAC)
    end
  end

  describe "listening" do
    it "pulls NRFD with PB1 low" do
      listen(0x04)
      expect(low_lines & (ieee::NRFD | ieee::NDAC)).to eq(ieee::NRFD)
    end

    it "pulls NDAC with PB2 low" do
      listen(0x02)
      expect(low_lines & (ieee::NRFD | ieee::NDAC)).to eq(ieee::NDAC)
    end

    it "reads the data lines' levels on port A" do
      listen(0x06)
      pull(0x5a)
      expect(drive.bus.peek(0x1801)).to eq(0xa5)
    end

    it "reads DAV low on PB6 while the controller pulls it" do
      listen(0x06)
      pull(ieee::DAV)
      expect(drive.bus.peek(0x1800) & 0x40).to eq(0)
    end

    it "reads EOI low on PB3 while the controller pulls it" do
      listen(0x06)
      pull(ieee::EOI)
      expect(drive.bus.peek(0x1800) & 0x08).to eq(0)
    end

    it "drives no data lines from port A" do
      listen(0x07)
      drive.bus.poke(0x1803, 0xff)
      drive.bus.poke(0x1801, 0x00)
      expect(low_lines & ieee::DIO).to eq(0)
    end
  end

  describe "talking" do
    it "drives the data lines from port A, a 0 pulling a line low" do
      talk(0x58, 0xa5)
      expect(low_lines & ieee::DIO).to eq(0x5a)
    end

    it "pulls DAV with PB6 low" do
      talk(0x18)
      expect(low_lines & ieee::DAV).to eq(ieee::DAV)
    end

    it "pulls EOI with PB3 low" do
      talk(0x50)
      expect(low_lines & ieee::EOI).to eq(ieee::EOI)
    end

    it "leaves EOI to the bus while ATN is low" do
      talk(0x51)
      pull(ieee::ATN)
      expect(low_lines & ieee::EOI).to eq(0)
    end

    it "reads NRFD low on PB1 while the controller pulls it" do
      talk(0x58)
      pull(ieee::NRFD)
      expect(drive.bus.peek(0x1800) & 0x02).to eq(0)
    end

    it "leaves NRFD and NDAC to the bus" do
      talk(0x58)
      expect(low_lines & (ieee::NRFD | ieee::NDAC)).to eq(0)
    end
  end

  describe "the device number jumpers" do
    # PB0 and PB1 as inputs, with CA2 low.
    def jumpers(device)
      drive = described_class.new(rom: stub_rom, device:)
      drive.bus.poke(0x1802, 0x30)
      drive.bus.poke(0x180c, 0x0c)
      drive.bus.peek(0x1800) & 0x03
    end

    it "read low on PB0 and PB1 for device 8" do
      expect(jumpers(8)).to eq(0)
    end

    it "read high on PB0 and PB1 for device 11" do
      expect(jumpers(11)).to eq(3)
    end

    it "read high on PB1 for device 10" do
      expect(jumpers(10)).to eq(2)
    end

    it "let go of PB0 and PB1 while CA2 is high" do
      drive.bus.poke(0x1802, 0x30)
      expect(drive.bus.peek(0x1800) & 0x03).to eq(3)
    end
  end

  it "runs the disk mechanism from VIA 2, as the 1541 does" do
    drive.bus.poke(0x1c02, 0x6f)
    drive.bus.poke(0x1c00, 0x04)
    expect(drive.mechanism).to be_motor_on
  end

  describe "on a bus with the controller" do
    let(:bus) { Badline::Drives::IEEEBus.new }

    before { drive.connect(bus) }

    it "is one of its drives" do
      expect(bus.drives).to eq([drive])
    end

    it "leaves the bus it was on" do
      drive.connect(Badline::Drives::IEEEBus.new)
      expect(bus.drives).to be_empty
    end
  end

  describe "with the DOS", :slow do
    # Whether the drive was asleep once booted, whether it still was a
    # host cycle after the controller pulled ATN, and the address it
    # listens to.
    let(:booted) do
      TakenOnce.fetch(:drive2031_booted) do
        drive = described_class.new(device: 9)
        described_class::BOOT_CYCLES.times { drive.host_cycle! }
        asleep = drive.asleep?
        drive.ieee_bus.host_lines = Badline::Drives::IEEEBus::ATN
        drive.host_cycle!
        [asleep, drive.asleep?, drive.ram.peek(0x77)]
      end
    end

    it "comes to sleep in its idle loop" do
      expect(booted[0]).to be(true)
    end

    it "wakes when the controller pulls ATN" do
      expect(booted[1]).to be(false)
    end

    it "listens as the device its jumpers set" do
      expect(booted[2]).to eq(0x29)
    end
  end
end
