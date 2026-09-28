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
  let(:dir) { Dir.mktmpdir }
  let(:disk) do
    Badline::Drive1541::Disk.from_d64(Badline::Storage::D64Image.new(blank_d64(File.join(dir, "blank.d64"))))
  end

  after { FileUtils.remove_entry(dir) }

  # VIA 2 set up the way the DOS reads: PB0-3 and PB5-6 outputs, CA1 on
  # its falling edge, CA2 (SOE) and CB2 (read mode) high, and port A
  # latched on CA1. Phase 0 holds the head on track 18 while the motor
  # runs, and the motor stops.
  before do
    drive.ram.write(0x0300, [0x4c, 0x00, 0x03]) # JMP *
    via.poke(0x1c02, 0x6f)
    via.poke(0x1c0c, 0xee)
    via.poke(0x1c0b, 0x01)
    port_b(0x04)
    port_b(0x00)
  end

  def port_b(value) = via.poke(0x1c00, value)

  # Motor on, at the bit rate of the zone, the stepper where it is.
  def spin(zone) = port_b(0x04 | (zone << 5))

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

  # Steps through the phases with the motor on, which powers the stepper.
  def step(phases)
    phases.each { |phase| port_b(0x04 | phase) }
  end

  describe "at power-on" do
    subject(:mechanism) { Badline::Drive1541.new(rom: Drive1541ROM.stub).mechanism }

    # Port B's lines float high until the DOS sets it up.
    it "turns the motor and lights the LED" do
      expect([mechanism.motor_on?, mechanism.led_on?]).to eq([true, true])
    end

    # Phase 3 pulls it from track 18 to the half track outside it.
    it "has the head a half track out from track 18" do
      expect(mechanism.half_track).to eq(35)
    end

    it "has it back on track 18 once phase 0 holds it with the motor on" do
      mechanism.port_b_written(0x04)
      expect(mechanism.half_track).to eq(36)
    end

    it "leaves it there while the motor is off" do
      mechanism.port_b_written(0x00)
      expect(mechanism.half_track).to eq(35)
    end
  end

  describe "port B" do
    it "turns the motor on with PB2" do
      expect { port_b(0x04) }.to change(mechanism, :motor_on?).from(false).to(true)
    end

    it "lights the LED with PB3" do
      expect { port_b(0x08) }.to change(mechanism, :led_on?).from(false).to(true)
    end

    it "selects the bit rate with PB5-6" do
      port_b(0x40)
      expect(mechanism.zone).to eq(2)
    end

    it "reads the sensor open on PB4 with no disk in" do
      expect(via.peek(0x1c00) & 0x10).to eq(0x10)
    end

    it "reads a writable disk on PB4" do
      drive.insert(disk)
      expect(via.peek(0x1c00) & 0x10).to eq(0x10)
    end

    it "reads a write-protected disk low on PB4" do
      allow(disk).to receive(:write_protected?).and_return(true)
      drive.insert(disk)
      expect(via.peek(0x1c00) & 0x10).to eq(0)
    end
  end

  describe "the stepper" do
    # The 92 phases stepping out from phase 0, as the DOS's bump does.
    let(:bump) { Array.new(92) { |n| (-1 - n) & 3 } }

    it "moves the head in a half track for each phase step up" do
      step([1, 2, 3])
      expect(mechanism.half_track).to eq(39)
    end

    it "moves the head out a half track for each phase step down" do
      step([3, 2, 1, 0])
      expect(mechanism.half_track).to eq(32)
    end

    it "leaves the head where it is for a jump of two phases" do
      step([2])
      expect(mechanism.half_track).to eq(36)
    end

    it "stops the head at track 1" do
      step(bump)
      expect(mechanism.half_track).to eq(2)
    end

    # Each step out against the stop slips the phases round, so the bump
    # leaves phase 0 holding track 1. The DOS then formats track 1 and
    # steps in by two phases for each track after it. See "1541 disk
    # mechanism" in doc/pinned-behaviour.md.
    it "steps in from the stop with the first phase after the bump" do
      step(bump)
      expect([1, 2, 3, 0].map { |phase| step([phase]) && mechanism.half_track }).to eq([3, 4, 5, 6])
    end

    it "holds the head against the stop through the bump" do
      step(bump.first(40))
      expect(bump.drop(40).map { |phase| step([phase]) && mechanism.half_track }.uniq).to eq([2])
    end

    # Phase 2 holds track 18 after the bump, so phase 1 is a step out.
    it "keeps the slipped phases once off the stop" do
      step(bump)
      step(Array.new(34) { |n| (n + 1) & 3 })
      expect([mechanism.half_track, step([1]) && mechanism.half_track]).to eq([36, 35])
    end

    it "stops the head at track 42" do
      step(Array.new(60) { |n| (n + 1) & 3 })
      expect(mechanism.half_track).to eq(84)
    end

    # The motor's line powers the stepper's coils too.
    it "doesn't step with the motor off" do
      port_b(0x01)
      expect(mechanism.half_track).to eq(36)
    end

    it "pulls the head to the phase set with the motor off once the motor comes on" do
      port_b(0x01)
      port_b(0x05)
      expect(mechanism.half_track).to eq(37)
    end
  end

  describe "the write electronics" do
    let(:disk) { Badline::Drive1541::Disk.new }
    let(:gcr) { Badline::Drive1541::GCR }

    # Write mode as the DOS sets it: port A all outputs, CB2 low.
    def write_mode
      via.poke(0x1c03, 0xff)
      via.poke(0x1c0c, 0xce)
    end

    def read_mode
      via.poke(0x1c0c, 0xee)
      via.poke(0x1c03, 0x00)
    end

    # Each byte goes to port A after a BYTE READY, as the DOS's write loop
    # does, and loads at the next one. One more byte time writes the last.
    def write_bytes(bytes)
      bytes.each do |byte|
        via.poke(0x1c01, byte)
        next_byte
      end
      next_byte
    end

    def bits(track) = track.bytes.pack("C*").unpack1("B*")

    # A sector as the DOS writes it: SYNC, header, gap, SYNC and data.
    def sector(track, sector, data)
      disk_class = Badline::Drive1541::Disk
      ([0xff] * 5) + gcr.encode(disk_class.header(track, sector, [0x41, 0x42], nil)) + ([0x55] * 9) +
        ([0xff] * 5) + gcr.encode(disk_class.data_block(data, nil))
    end

    before do
      drive.insert(disk)
      spin(2)
      write_mode
    end

    it "writes each byte, most significant bit first, onto the track" do
      write_bytes([0x12, 0x34, 0x56, 0x78])
      expect(bits(disk.track(36))).to include("00010010001101000101011001111000")
    end

    it "gives a half track without data a blank track to write on" do
      write_bytes([0x5a])
      expect([disk.track(36).length, disk.written?]).to eq([7142, true])
    end

    it "still signals BYTE READY for each byte" do
      next_byte
      expect(Array.new(10) { next_byte }).to all(eq(28))
    end

    # The head starts writing wherever it is, so the sector lands at a bit
    # offset the stored bytes don't line up with.
    it "writes a sector that reads back at whatever bit it started on" do
      data = Array.new(256) { |i| (i * 13) & 0xff }
      run(37)
      write_bytes(sector(18, 5, data))
      found = Badline::Drive1541::SectorReader.read(disk.track(36).bytes, 18)[5]
      expect(found.data[1, 256]).to eq(data)
    end

    it "reads back what it wrote once in read mode" do
      write_bytes(([0xff] * 5) + [0x52, 0x94, 0xa5, 0x29, 0x4a])
      read_mode
      drive.cycle! until mechanism.sync?
      drive.cycle! while mechanism.sync?
      expect(Array.new(5) { next_byte && via.peek(0x1c01) }).to eq([0x52, 0x94, 0xa5, 0x29, 0x4a])
    end

    context "with the disk write-protected" do
      let(:disk) do
        Badline::Drive1541::Disk.from_d64(Badline::Storage::D64Image.new(blank_d64(File.join(dir, "blank.d64"))))
      end

      before do
        allow(disk).to receive(:write_protected?).and_return(true)
        drive.insert(disk)
      end

      # The writeprotect testprog writes to track 18 without asking the
      # DOS, and expects the disk to stay as it was.
      it "keeps the write gate shut" do
        before = disk.track(36).bytes.dup
        write_bytes([0x00] * 100)
        expect([disk.track(36).bytes == before, disk.written?]).to eq([true, false])
      end
    end

    describe "writing back" do
      before { allow(disk).to receive(:flush) }

      it "flushes the disk when the motor stops" do
        write_bytes([0x5a])
        port_b(0x00)
        expect(disk).to have_received(:flush)
      end

      it "flushes the disk when it comes out" do
        write_bytes([0x5a])
        drive.insert(nil)
        expect(disk).to have_received(:flush)
      end

      it "warns and carries on when the image won't take the write" do
        allow(disk).to receive(:flush).and_raise(Badline::Storage::WriteError, "WRITE PROTECT ON")
        write_bytes([0x5a])
        expect { port_b(0x00) }.to output(/couldn't write the disk back/).to_stderr
      end

      it "leaves a disk nothing was written to alone" do
        read_mode
        run(1000)
        drive.insert(nil)
        expect(disk).not_to have_received(:flush)
      end
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
