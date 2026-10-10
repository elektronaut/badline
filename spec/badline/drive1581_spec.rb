# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require "badline/c128"
require_relative "../support/blank_disk"
require_relative "../support/snapshot_scenarios"
require_relative "../support/taken_once"

describe Badline::Drive1581 do
  include SnapshotScenarios
  include BlankDisk

  subject(:drive) { described_class.new(rom: stub_rom) }

  # A 32 KB stand-in for the DOS at $8000-$FFFF: NOPs, with the reset and
  # IRQ vectors pointing into drive RAM.
  let(:stub_rom) do
    bytes = Array.new(0x8000, 0xea)
    bytes[0x7ffc, 4] = [0x00, 0x03, 0x00, 0x04]
    Badline::ROM.new(bytes, length: 0x8000, start: 0x8000)
  end

  let(:serial_bus) { Badline::IECBus.new.tap { |bus| bus.host_lines = 0x07 } }

  def run(cycles) = cycles.times { drive.cycle! }

  def load(bytes, at: 0x0300) = drive.ram.write(at, bytes)

  # The 8520's port A driven as the DOS drives it: PA0, PA2, PA5 and PA6
  # out.
  def port_a(value)
    drive.bus.poke(0x4002, 0x65)
    drive.bus.poke(0x4000, value)
  end

  # Port B driven as the DOS drives it: PB1, PB3, PB4 and PB5 out.
  def port_b(value)
    drive.bus.poke(0x4003, 0x3a)
    drive.bus.poke(0x4001, value)
  end

  describe "the bus" do
    it "reads the ROM's reset vector from $FFFC" do
      expect(drive.cpu.program_counter).to eq(0x0300)
    end

    it "has 8 KB of RAM" do
      drive.bus.poke(0x1fff, 0x42)
      expect(drive.ram.peek(0x1fff)).to eq(0x42)
    end

    it "finds open bus at $2000-$3FFF" do
      drive.bus.peek(0x8123)
      expect(drive.bus.peek(0x2000)).to eq(0xea)
    end

    it "mirrors the 8520's registers through $4000-$5FFF" do
      drive.bus.poke(0x5ff4, 0x42) # timer A's latch, low byte
      expect(drive.cia.timer_a_latch & 0xff).to eq(0x42)
    end

    it "mirrors the WD1772's registers through $6000-$7FFF" do
      drive.bus.poke(0x7ff5, 0x12)
      expect(drive.bus.peek(0x6001)).to eq(0x12)
    end

    it "takes an IRQ from the 8520" do
      # LDA #$82; STA ICR; LDA #$20; STA TBL; LDA #$00; STA TBH; LDA #$11; STA CRB; CLI; JMP *
      load([0xa9, 0x82, 0x8d, 0x0d, 0x40, 0xa9, 0x20, 0x8d, 0x06, 0x40, 0xa9, 0x00, 0x8d, 0x07, 0x40,
            0xa9, 0x11, 0x8d, 0x0f, 0x40, 0x58, 0x4c, 0x15, 0x03])
      load([0xe6, 0x10, 0xad, 0x0d, 0x40, 0x40], at: 0x0400) # INC $10; LDA ICR; RTI
      run(200)
      expect(drive.ram.peek(0x10)).to be_positive
    end
  end

  describe "port A" do
    it "runs the motor with PA2 low" do
      port_a(0x00)
      expect(drive.mechanism).to be_motor_on
    end

    it "stops it with PA2 high" do
      port_a(0x04)
      expect(drive.mechanism).not_to be_motor_on
    end

    it "selects side 1 with PA0 high" do
      port_a(0x05)
      expect(drive.mechanism.side).to eq(1)
    end

    it "lights the activity LED with PA6 high" do
      port_a(0x44)
      expect(drive.led_on?).to be(true)
    end

    it "lights the power LED with PA5 high" do
      port_a(0x24)
      expect(drive.power_led_on?).to be(true)
    end

    it "reads both device switches closed for device 8" do
      expect(drive.cia.peek(0x4000) & 0x18).to eq(0)
    end

    it "reads the switches for device 11 open" do
      expect(described_class.new(rom: stub_rom, device: 11).cia.peek(0x4000) & 0x18).to eq(0x18)
    end

    it "reads the disk change line low at power-on" do
      expect(drive.cia.peek(0x4000) & 0x80).to eq(0)
    end

    it "reads /RDY low with a disk turning" do
      drive.insert(Badline::Drive1581::Disk.new)
      port_a(0x00)
      expect(drive.cia.peek(0x4000) & 0x02).to eq(0)
    end

    it "reads /RDY high without a disk" do
      port_a(0x00)
      expect(drive.cia.peek(0x4000) & 0x02).to eq(0x02)
    end
  end

  describe "the serial bus" do
    before { drive.connect(serial_bus) }

    it "pulls DATA with PB1 high" do
      port_b(0x02)
      expect(serial_bus.data_low?).to be(true)
    end

    it "pulls CLK with PB3 high" do
      port_b(0x08)
      expect(serial_bus.clk_low?).to be(true)
    end

    it "pulls DATA as ATN goes low with PB4 high" do
      port_b(0x10)
      serial_bus.host_lines = 0x0f
      expect(serial_bus.data_low?).to be(true)
    end

    it "lets DATA go with ATN high, whatever PB4 holds" do
      port_b(0x00)
      expect(serial_bus.data_low?).to be(false)
    end

    it "lets DATA go as ATN goes low with PB4 low" do
      port_b(0x00)
      serial_bus.host_lines = 0x0f
      expect(serial_bus.data_low?).to be(false)
    end

    it "reads ATN IN on PB7 a host cycle after ATN goes low" do
      serial_bus.host_lines = 0x0f
      drive.host_cycle!
      expect(drive.cia.peek(0x4001) & 0x80).to eq(0x80)
    end

    it "flags ATN going low on FLAG" do
      serial_bus.host_lines = 0x0f
      2.times { drive.host_cycle! }
      expect(drive.cia.interrupt_status.value & 0x10).to eq(0x10)
    end

    it "reads the write-protect line low with no disk" do
      expect(drive.cia.peek(0x4001) & 0x40).to eq(0)
    end
  end

  describe "fast serial" do
    before do
      drive.connect(serial_bus)
      load([0x4c, 0x00, 0x03]) # JMP *
    end

    # The SRQ levels at each host cycle, for +cycles+ of them.
    def srq_pulses(cycles)
      levels = Array.new(cycles) do
        drive.host_cycle!
        serial_bus.low_lines & Badline::IECBus::SRQ
      end
      levels.chunk_while { |a, b| a == b }.count { |run| run.first.positive? }
    end

    it "turns the buffers outwards with PB5 high" do
      port_b(0x20)
      expect(drive.fast_serial_out).to be(true)
    end

    it "clocks a byte out on SRQ with PB5 high" do
      port_b(0x20)
      [[0x4004, 4], [0x4005, 0], [0x400e, 0x51], [0x400c, 0xa5]].each { |addr, value| drive.bus.poke(addr, value) }
      expect(srq_pulses(200)).to eq(8)
    end

    it "lets SRQ go with PB5 low" do
      port_b(0x00)
      drive.bus.poke(0x400e, 0x40)
      expect(srq_pulses(10)).to eq(0)
    end
  end

  describe "the 8520's TOD pin" do
    it "never counts the event counter" do
      drive.bus.poke(0x4008, 0)
      run(100_000)
      expect(drive.cia.peek(0x4008)).to eq(0)
    end
  end

  describe "#insert_image" do
    let(:dir) { Dir.mktmpdir }

    after { FileUtils.remove_entry(dir) }

    it "puts in a .d81" do
      drive.insert_image(blank_d81(File.join(dir, "disk.d81")), read_only: true)
      expect(drive.disk.track(39, 0).sectors.length).to eq(10)
    end
  end

  describe "#save_state" do
    let(:target) { described_class.new(rom: stub_rom) }

    it "restores the drive as it was saved" do
      load([0xa9, 0x24, 0x8d, 0x00, 0x40, 0x4c, 0x05, 0x03]) # LDA #$24; STA PRA; JMP *
      port_a(0x24)
      run(101)
      round_trip(drive, target)
      expect(state_differences(drive, target)).to be_empty
    end
  end

  context "with its DOS", :slow do
    # A 1581 without a disk, run from power-on until it sleeps through its
    # idle loop.
    subject(:drive) do
      TakenOnce.fetch(:drive1581_booted) do
        described_class.new.tap do |booted|
          booted.connect(Badline::IECBus.new.tap { |bus| bus.host_lines = 0x07 })
          3_000_000.times do
            booted.host_cycle!
            break if booted.asleep?
          end
        end
      end
    end

    it "sleeps through its idle loop" do
      expect(drive).to be_asleep
    end

    it "sleeps at the loop's start" do
      expect(drive.cpu.program_counter).to eq(described_class::IDLE_LOOP)
    end

    it "takes its WD1772 for one, as the TOD pin tells it" do
      expect(drive.ram.peek(0x01da)).to eq(0x09)
    end
  end
end
