# frozen_string_literal: true

require "spec_helper"
require "badline/drives/model8050"
require "tmpdir"
require_relative "../../support/taken_once"
require_relative "../../support/blank_disk"

describe Badline::Drives::Model8050 do
  subject(:drive) { described_class.new(dos_rom: stub_dos, fdc_rom: stub_fdc) }

  let(:ieee) { Badline::Drives::IEEEBus }

  # NOPs, with each processor's reset vector at its own RAM.
  let(:stub_dos) do
    bytes = Array.new(0x4000, 0xea)
    bytes[0x3ffc, 2] = [0x00, 0x10]
    Badline::ROM.new(bytes, length: 0x4000, start: 0xc000)
  end

  let(:stub_fdc) do
    Array.new(0x400, 0xea).tap { |bytes| bytes[0x3fc, 2] = [0x00, 0x04] }
  end

  describe "the interface processor's bus" do
    let(:bus) { drive.ip_bus }

    it "puts UC1's RAM at $00 and UE1's at $80, mirrored at $0100" do
      bus.poke(0x0105, 0x11)
      bus.poke(0x0085, 0x22)
      expect([drive.data_riot.read_ram(0x05), drive.control_riot.read_ram(0x05)]).to eq([0x11, 0x22])
    end

    it "puts UC1's registers at $0200 and UE1's at $0280" do
      bus.poke(0x0201, 0x0f)
      bus.poke(0x0283, 0x38)
      expect([drive.data_riot.peek(0x01), drive.control_riot.peek(0x03)]).to eq([0x0f, 0x38])
    end

    it "gives each 4 KB block from $1000 one 1 KB of the common RAM, mirrored" do
      bus.poke(0x2c05, 0x5a)
      expect(drive.common.peek(0x0405)).to eq(0x5a)
    end

    it "reads the last byte on the data bus from open bus" do
      bus.peek(0xc000)
      expect(bus.peek(0x8000)).to eq(0xea)
    end
  end

  describe "the buses' volatile reads" do
    it "marks a read of a RIOT's timer" do
      drive.ip_bus.peek(0x0284)
      expect(drive.ip_bus.volatile).to be(true)
    end

    it "leaves a read of a RIOT's ports alone" do
      drive.ip_bus.peek(0x0282)
      expect(drive.ip_bus.volatile).to be(false)
    end

    it "marks a read of the VIA's timer 1" do
      drive.fdc_bus.peek(0x0044)
      expect(drive.fdc_bus.volatile).to be(true)
    end

    it "marks a read of the 6530's interrupt flag" do
      drive.fdc_bus.peek(0x0087)
      expect(drive.fdc_bus.volatile).to be(true)
    end

    it "leaves a read of the VIA's port A alone" do
      drive.fdc_bus.peek(0x0041)
      expect(drive.fdc_bus.volatile).to be(false)
    end
  end

  describe "the floppy controller's bus" do
    let(:bus) { drive.fdc_bus }

    it "puts the 6530's RAM at $00, its stack at $0100" do
      bus.poke(0x013f, 0x5a)
      expect(drive.rriot.read_ram(0x3f)).to eq(0x5a)
    end

    it "puts the VIA at $40 and the 6530's registers at $80" do
      bus.poke(0x0043, 0xff)
      bus.poke(0x0083, 0x17)
      expect([drive.via.peek(0x43), drive.rriot.peek(0x03)]).to eq([0xff, 0x17])
    end

    it "shares the common RAM at $0400 with the IP's $1000" do
      drive.ip_bus.poke(0x4003, 0x77)
      expect(bus.peek(0x1003)).to eq(0x77)
    end

    it "runs the 6530's ROM at $FC00, A13-A15 undecoded" do
      expect([bus.peek(0xfffc), bus.peek(0x1ffd)]).to eq([0x00, 0x04])
    end
  end

  describe "the IEEE-488 port" do
    # UE1 set up as the DOS leaves it to listen: PA0-PA4 out.
    def control(value)
      drive.ip_bus.poke(0x0281, 0x1f)
      drive.ip_bus.poke(0x0280, value)
    end

    def pull(lines)
      drive.ieee_bus.host_lines = lines
      drive.host_cycle!
    end

    it "leaves the bus alone as the DOS idles" do
      control(0x1c)
      expect(drive.ieee_low_lines(false)).to eq(0)
    end

    it "pulls NDAC while PA1 is set, and NRFD while PA2 is clear" do
      control(0x1a)
      expect(drive.ieee_low_lines(false)).to eq(ieee::NDAC | ieee::NRFD)
    end

    it "pulls NRFD and NDAC while ATN and ATNA differ" do
      control(0x1c)
      expect(drive.ieee_low_lines(true)).to eq(ieee::NDAC | ieee::NRFD)
    end

    it "drives the data lines from UC1's port B" do
      drive.ip_bus.poke(0x0203, 0xff)
      drive.ip_bus.poke(0x0202, 0xbd)
      expect(drive.ieee_low_lines(false) & ieee::DIO).to eq(0x42)
    end

    it "reads the data lines on UC1's port A" do
      pull(0x81)
      expect(drive.ip_bus.peek(0x0200)).to eq(0x7e)
    end

    it "reads DAV and EOI on UE1's PA6 and PA5, and ATN high on PA7 from the cycle after" do
      pull(ieee::DAV | ieee::ATN)
      drive.cycle!
      expect(drive.ip_bus.peek(0x0280) & 0xe0).to eq(0xa0)
    end

    it "sets UE1's PA7 flag as ATN goes low" do
      pull(ieee::ATN)
      drive.cycle!
      expect(drive.ip_bus.peek(0x0285) & 0x40).to eq(0x40)
    end

    it "reads NRFD and NDAC on UE1's PB7 and PB6" do
      control(0x1c)
      pull(ieee::NRFD)
      expect(drive.ip_bus.peek(0x0282) & 0xc0).to eq(0x40)
    end

    it "reads the device number off the jumpers on UE1's PB0-PB2" do
      unit = described_class.new(dos_rom: stub_dos, fdc_rom: stub_fdc, device: 13)
      expect(unit.ip_bus.peek(0x0282) & 0x07).to eq(5)
    end

    it "refuses a device number the jumpers can't set" do
      expect { described_class.new(dos_rom: stub_dos, fdc_rom: stub_fdc, device: 16) }.to raise_error(ArgumentError)
    end
  end

  describe "the drives" do
    it "say one side to the 6530's PB6" do
      expect(drive.fdc_bus.peek(0x0082) & 0x40).to eq(0x40)
    end

    it "say two sides on the 8250" do
      unit = Badline::Drives::Model8250.new(dos_rom: stub_dos, fdc_rom: stub_fdc)
      expect(unit.fdc_bus.peek(0x0082) & 0x40).to eq(0)
    end
  end

  # The board running DOS 2.7 and the MPI mask from reset, which takes the
  # IP about 640,000 cycles.
  describe "booting", :slow do
    def booted(model, device: 8)
      TakenOnce.fetch([:model8050_boot, model, device]) do
        model.new(device:).tap { |unit| 700_000.times { unit.cycle! } }
      end
    end

    it "brings the IP to its idle loop and the FDC to its job loop" do
      unit = booted(described_class)
      expect([unit.ip_cpu.program_counter, unit.fdc_cpu.program_counter]).to all(be_between(0xc5a0, 0xffff))
    end

    # xcbm2 and xpet with -drive8type 8050 -drive8truedrive read the same
    # from the IP's $1099 and $10B0 once booted.
    it "leaves the zone tables in the common RAM" do
      unit = booted(described_class)
      tables = [0x99, 0x9a, 0x9b, 0x9c, 0xb0, 0xb1, 0xb2, 0xb3].map { |addr| unit.common.peek(addr) }
      expect(tables).to eq([0x17, 0x19, 0x1b, 0x1d, 0x4e, 0x41, 0x36, 0x28])
    end

    it "listens and talks as the jumpers' device" do
      unit = booted(described_class, device: 13)
      expect([unit.ip_bus.peek(0x0c), unit.ip_bus.peek(0x0d)]).to eq([0x2d, 0x4d])
    end

    it "boots the 8250 alike" do
      unit = booted(Badline::Drives::Model8250)
      expect(unit.ip_cpu.program_counter).to be_between(0xc5a0, 0xc611)
    end
  end

  # A unit sleeping through its idle loops beside one stepping every cycle,
  # each on a bus of its own with the controller's lines released, through
  # boot and on into the idle loops.
  describe "idling", :slow do
    def idle_pair
      TakenOnce.fetch(:model8050_idle) do
        units = [true, false].map { |skip| described_class.new.tap { |unit| unit.idle_skip = skip } }
        asleep = 0
        alone = 0
        1_500_000.times do
          units.each(&:host_cycle!)
          sleeper = units.first
          asleep += 1 if sleeper.asleep?
          alone += 1 if sleeper.dozing? && !sleeper.asleep?
        end
        [units, asleep, alone]
      end
    end

    def state(unit)
      [unit.cycles, unit.ip_cpu.cycles, unit.ip_cpu.instructions, *unit.ip_cpu.idle_state, unit.fdc_cpu.cycles,
       unit.fdc_cpu.instructions, *unit.fdc_cpu.idle_state, unit.rriot.timer.counter, *unit.rriot.idle_state,
       unit.control_riot.timer.counter, *unit.control_riot.idle_state, unit.via.timer1, *unit.common.snapshot]
    end

    it "sleeps through most of the idle loops after boot" do
      expect(idle_pair[1]).to be > 600_000
    end

    it "wakes only the controller's side for the 6530's timer" do
      expect(idle_pair.last).to be_between(1, idle_pair[1] / 10)
    end

    it "holds the same as a unit stepping every cycle" do
      units = idle_pair.first
      expect(state(units.first)).to eq(state(units.last))
    end
  end

  # DOS 2.7's controller running jobs the way the IP leaves them in the
  # common RAM: a code at $1003 + n, its header at $1021 + 8n (ID, track,
  # sector) and its buffer at $1100 + $100n, for drive 0. The DOS bumps the
  # head to track 1 first; here the controller is told it's there.
  describe "running jobs", :slow do
    extend BlankDisk

    def self.run_job(unit, code, track, sector)
      [0x41, 0x42, track, sector].each_with_index { |byte, index| unit.common.poke(0x21 + index, byte) }
      unit.common.poke(0x03, code)
      unit.cycle! while unit.common.peek(0x03) >= 0x80
      unit.common.peek(0x03)
    end

    # Reads the header block, then writes 39/5 and flushes.
    def self.results
      TakenOnce.fetch(:model8050_jobs) do
        unit = described_class.new
        unit.insert_image(blank_d80(File.join(Dir.mktmpdir, "jobs.d80"), name: "JOBS", id: "AB"))
        700_000.times { unit.cycle! }
        unit.fdc_bus.poke(0x21, 1)
        read = [run_job(unit, 0x80, 39, 0), (0..255).map { |offset| unit.common.peek(0x100 + offset) }]
        256.times { |offset| unit.common.poke(0x100 + offset, offset) }
        written = run_job(unit, 0x90, 39, 5)
        unit.flush
        read + [written, unit.disk.image.read_block(39, 5)]
      end
    end

    it "reads a block off the disk" do
      expect(self.class.results[0]).to eq(0x01)
    end

    it "reads the disk's name from the header block" do
      expect(self.class.results[1][6, 4].pack("C*")).to eq("JOBS")
    end

    it "writes a block and verifies it" do
      expect(self.class.results[2]).to eq(0x01)
    end

    it "stores the block it wrote in the image once flushed" do
      expect(self.class.results[3]).to eq((0..255).to_a)
    end
  end
end
