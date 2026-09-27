# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require_relative "../../support/blank_disk"
require_relative "../../support/drive1541_rom"

describe Badline::Drive1541::Mechanism do
  include BlankDisk

  subject(:mechanism) { drive.mechanism }

  let(:drive) { Badline::Drive1541.new(rom: Drive1541ROM.stub) }
  let(:via) { drive.via2 }
  let(:disk) do
    Dir.mktmpdir do |dir|
      Badline::Drive1541::Disk.from_d64(Badline::Storage::D64Image.new(blank_d64(File.join(dir, "blank.d64"))))
    end
  end

  # VIA 2 set up the way the DOS reads: PB0-3 and PB5-6 outputs, CA1 on
  # its falling edge, CA2 (SOE) and CB2 (read mode) high, and port A
  # latched on CA1.
  before do
    drive.ram.write(0x0300, [0x4c, 0x00, 0x03]) # JMP *
    via.poke(0x1c02, 0x6f)
    via.poke(0x1c0c, 0xee)
    via.poke(0x1c0b, 0x01)
    port_b(0x03)
  end

  def port_b(value) = via.poke(0x1c00, value)

  # Motor on, at the bit rate of the zone, the stepper where it is.
  def spin(zone) = port_b(0x07 | (zone << 5))

  def run(cycles) = cycles.times { drive.cycle! }

  # Runs until the next BYTE READY and returns the cycles it took.
  def next_byte(limit = 1000)
    via.poke(0x1c0d, 0x02)
    (1..limit).each do |n|
      drive.cycle!
      return n if via.interrupt_flags.anybits?(0x02)
    end
    nil
  end

  def step(phases)
    phases.each { |phase| port_b(phase) }
  end

  describe "at power-on" do
    subject(:mechanism) { Badline::Drive1541.new(rom: Drive1541ROM.stub).mechanism }

    # Port B's lines float high until the DOS sets it up.
    it "turns the motor and lights the LED" do
      expect([mechanism.motor_on?, mechanism.led_on?]).to eq([true, true])
    end

    it "has the head on track 18" do
      expect(mechanism.half_track).to eq(36)
    end
  end

  describe "port B" do
    it "turns the motor on with PB2" do
      expect { port_b(0x07) }.to change(mechanism, :motor_on?).from(false).to(true)
    end

    it "lights the LED with PB3" do
      expect { port_b(0x0b) }.to change(mechanism, :led_on?).from(false).to(true)
    end

    it "selects the bit rate with PB5-6" do
      port_b(0x43)
      expect(mechanism.zone).to eq(2)
    end

    it "reads the disk as writable on PB4" do
      expect(via.peek(0x1c00) & 0x10).to eq(0x10)
    end
  end

  describe "the stepper" do
    # The phases stepping out from 3, as the DOS's bump does.
    let(:bump) { Array.new(48) { |n| (2 - n) & 3 } }

    it "moves the head in a half track for each phase step up" do
      step([0, 1, 2])
      expect(mechanism.half_track).to eq(39)
    end

    it "moves the head out a half track for each phase step down" do
      step([2, 1, 0, 3])
      expect(mechanism.half_track).to eq(32)
    end

    it "leaves the head where it is for a jump of two phases" do
      step([1])
      expect(mechanism.half_track).to eq(36)
    end

    it "stops the head at track 1" do
      step(bump)
      expect(mechanism.half_track).to eq(2)
    end

    it "steps in from the stop again at once" do
      step(bump)
      step([(bump.last + 1) & 3, (bump.last + 2) & 3])
      expect(mechanism.half_track).to eq(4)
    end

    it "stops the head at track 42" do
      step(Array.new(60) { |n| n & 3 })
      expect(mechanism.half_track).to eq(84)
    end

    it "steps with the motor off" do
      port_b(0x00)
      expect(mechanism.half_track).to eq(37)
    end
  end

  describe "the read electronics" do
    before { drive.insert(disk) }

    # With no disk in, the head reads only 0 bits, so no SYNC mark
    # breaks the framing.
    { 3 => 26, 2 => 28, 1 => 30, 0 => 32 }.each do |zone, cycles|
      it "has a byte ready every #{cycles} cycles in zone #{zone}" do
        drive.insert(nil)
        spin(zone)
        next_byte
        expect(Array.new(100) { next_byte }.sum).to eq(100 * cycles)
      end
    end

    it "reads nothing with the motor off" do
      expect(next_byte(1000)).to be_nil
    end

    it "reads 0 bits with no disk in" do
      drive.insert(nil)
      spin(3)
      next_byte
      expect(via.peek(0x1c01)).to eq(0x00)
    end

    it "keeps the bit rate PB5-6 select, whatever the track" do
      spin(0)
      drive.insert(nil)
      next_byte
      expect(next_byte).to eq(32)
    end

    # The cycles at which PB7 goes low, one for each SYNC mark.
    def sync_starts(cycles)
      low = false
      starts = []
      cycles.times do |n|
        drive.cycle!
        now = via.peek(0x1c00).nobits?(0x80)
        starts << n if now && !low
        low = now
      end
      starts
    end

    it "turns once in a track's length of bytes at its zone's rate, 200 ms" do
      spin(2)
      starts = sync_starts(250_000)
      expect(starts[39] - starts[1]).to eq(7142 * 28)
    end

    describe "SYNC" do
      it "reads low on PB7 for each SYNC mark, two a sector" do
        spin(2)
        expect(sync_starts(7142 * 28).length).to eq(2 * 19)
      end

      it "isn't detected in write mode, with CB2 low" do
        via.poke(0x1c0c, 0xce)
        spin(2)
        expect(sync_starts(7142 * 28)).to be_empty
      end

      it "holds BYTE READY off through the mark" do
        spin(2)
        drive.cycle! until mechanism.sync?
        via.poke(0x1c0d, 0x02)
        drive.cycle! while mechanism.sync?
        expect(via.interrupt_flags & 0x02).to eq(0)
      end

      it "frames a block's bytes from the first bit after the mark" do
        spin(2)
        drive.cycle! until mechanism.sync?
        drive.cycle! while mechanism.sync?
        bytes = Array.new(5) { next_byte && via.peek(0x1c01) }
        expect(Badline::Drive1541::GCR.decode(bytes)&.first).to eq(0x08).or eq(0x07)
      end
    end

    describe "BYTE READY" do
      before { spin(3) }

      it "sets VIA 2's CA1 flag" do
        expect(next_byte).not_to be_nil
      end

      it "latches the byte into port A" do
        next_byte
        latched = via.peek(0x1c01)
        run(10)
        expect(via.peek(0x1c01)).to eq(latched)
      end

      it "sets V through SO while CA2 is high" do
        drive.cpu.status.overflow = false
        next_byte
        expect(drive.cpu.status.overflow?).to be(true)
      end

      it "leaves V alone while CA2 is low" do
        via.poke(0x1c0c, 0xec)
        drive.cpu.status.overflow = false
        next_byte
        expect(drive.cpu.status.overflow?).to be(false)
      end
    end
  end
end
