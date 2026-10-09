# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require "badline/c128"
require_relative "../support/blank_disk"
require_relative "../support/snapshot_scenarios"

describe Badline::Drive1571 do
  include SnapshotScenarios

  subject(:drive) { described_class.new(rom: stub_rom) }

  # A 32 KB stand-in for DOS 3.0 at $8000-$FFFF: NOPs, with the reset and
  # IRQ vectors pointing into drive RAM.
  let(:stub_rom) do
    bytes = Array.new(0x8000, 0xea)
    bytes[0x7ffc, 4] = [0x00, 0x03, 0x00, 0x04]
    Badline::ROM.new(bytes, length: 0x8000, start: 0x8000)
  end

  def run(cycles) = cycles.times { drive.cycle! }

  def load(bytes, at: 0x0300) = drive.ram.write(at, bytes)

  # VIA 1's port A driven as the DOS drives it: PA1, PA2 and PA5 out.
  def port_a(value)
    drive.via1.poke(0x1803, 0x66)
    drive.via1.poke(0x1801, value)
  end

  describe "the bus" do
    it "reads the ROM's reset vector from $FFFC" do
      expect(drive.cpu.program_counter).to eq(0x0300)
    end

    it "mirrors the CIA's registers through $4000-$7FFF" do
      drive.bus.poke(0x7ff4, 0x42) # timer A's latch, low byte
      expect(drive.cia.timer_a_latch & 0xff).to eq(0x42)
    end

    it "keeps the WD1770's track register at $2001, mirrored" do
      drive.bus.poke(0x3ff5, 0x12)
      expect(drive.bus.peek(0x2001)).to eq(0x12)
    end

    it "reads the WD1770 idle" do
      expect(drive.bus.peek(0x2000)).to eq(0)
    end

    it "takes an IRQ from the CIA" do
      # LDA #$81; STA ICR; LDA #$20; STA TAL; LDA #$00; STA TAH; LDA #$19; STA CRA; CLI; JMP *
      load([0xa9, 0x81, 0x8d, 0x0d, 0x40, 0xa9, 0x20, 0x8d, 0x04, 0x40, 0xa9, 0x00, 0x8d, 0x05, 0x40,
            0xa9, 0x19, 0x8d, 0x0e, 0x40, 0x58, 0x4c, 0x15, 0x03])
      load([0xe6, 0x10, 0xad, 0x0d, 0x40, 0x40], at: 0x0400) # INC $10; LDA ICR; RTI
      run(200)
      expect(drive.ram.peek(0x10)).to be_positive
    end
  end

  describe "VIA 1's port A" do
    it "runs the drive at 2 MHz with PA5 high" do
      port_a(0x20)
      expect(drive).to be_fast
    end

    it "runs two drive cycles a host cycle at 2 MHz" do
      port_a(0x20)
      before = drive.cycles
      drive.host_cycle!
      expect(drive.cycles - before).to eq(2)
    end

    it "runs one at 1 MHz" do
      port_a(0x00)
      before = drive.cycles
      drive.host_cycle!
      expect(drive.cycles - before).to eq(1)
    end

    it "selects the second head with PA2 high" do
      port_a(0x04)
      expect(drive.mechanism.side).to eq(1)
    end

    it "turns the fast serial buffers outwards with PA1 high" do
      port_a(0x02)
      expect(drive.fast_serial_out).to be(true)
    end

    it "reads the track 0 sensor low on track 1" do
      drive.mechanism.instance_variable_set(:@half_track, 2)
      expect(drive.via1.peek(0x1801) & 0x01).to eq(0)
    end

    it "reads the track 0 sensor high elsewhere" do
      expect(drive.via1.peek(0x1801) & 0x01).to eq(1)
    end

    it "reads BYTE READY low on PA7 once it's signalled" do
      drive.mechanism.byte_ready!
      expect(drive.via1.peek(0x1801) & 0x80).to eq(0)
    end

    it "reads PA7 high again once the CPU reaches VIA 2" do
      drive.mechanism.byte_ready!
      drive.bus.peek(0x1c00)
      expect(drive.via1.peek(0x1801) & 0x80).to eq(0x80)
    end
  end

  describe "fast serial" do
    let(:bus) { Badline::IECBus.new.tap { |bus| bus.host_lines = 0x07 } }

    # VIA 1's port B lets CLK and DATA go, so only the fast serial pins
    # pull them.
    before do
      drive.connect(bus)
      drive.via1.poke(0x1802, 0x1a)
      drive.via1.poke(0x1800, 0x00)
    end

    # The SRQ and DATA levels at each host cycle, for +cycles+ of them.
    def lines(cycles)
      Array.new(cycles) do
        drive.host_cycle!
        bus.low_lines & (Badline::IECBus::SRQ | Badline::IECBus::DATA)
      end
    end

    # Clocks +byte+ in on SRQ and DATA as the host's CIA would, most
    # significant bit first.
    def clock_in(byte)
      7.downto(0) do |bit|
        data = byte[bit].zero? ? Badline::IECBus::DATA : 0
        bus.host_fast_lines = data | Badline::IECBus::SRQ
        4.times { drive.host_cycle! }
        bus.host_fast_lines = data
        4.times { drive.host_cycle! }
      end
    end

    it "clocks a byte out on SRQ, its bits on DATA, with PA1 out" do
      load([0x4c, 0x00, 0x03]) # JMP *
      port_a(0x02)
      [[0x4004, 4], [0x4005, 0], [0x400e, 0x51], [0x400c, 0xa5]].each { |addr, value| drive.bus.poke(addr, value) }
      expect(lines(200).chunk_while { |a, b| a == b }.count { |run| run.first.anybits?(Badline::IECBus::SRQ) })
        .to eq(8)
    end

    it "lets SRQ and DATA go with PA1 in" do
      port_a(0x00)
      drive.bus.poke(0x400e, 0x40)
      expect(lines(10).uniq).to eq([0])
    end

    it "takes a byte in from SRQ and DATA with PA1 in" do
      load([0x4c, 0x00, 0x03]) # JMP *
      port_a(0x00)
      clock_in(0x5a)
      expect(drive.cia.peek(0x400c)).to eq(0x5a)
    end
  end

  describe "#save_state" do
    let(:target) { described_class.new(rom: stub_rom) }

    it "restores the drive as it was saved" do
      load([0xa9, 0x24, 0x8d, 0x01, 0x18, 0x4c, 0x05, 0x03]) # LDA #$24; STA ORA; JMP *
      drive.via1.poke(0x1803, 0x66)
      run(101)
      round_trip(drive, target)
      expect(state_differences(drive, target)).to be_empty
    end
  end

  context "with DOS 3.0", :slow do
    subject(:drive) { described_class.new(host_clock_hz: 985_248) }

    before do
      bus = Badline::IECBus.new
      bus.host_lines = 0x07
      drive.connect(bus)
      1_200_000.times { drive.host_cycle! }
    end

    it "drops to 1 MHz once it has reset" do
      expect(drive).not_to be_fast
    end

    it "comes to its idle loop" do
      expect(drive.cpu.program_counter).to be_between(0xebff, 0xeca0)
    end
  end
end
