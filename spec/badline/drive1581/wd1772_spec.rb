# frozen_string_literal: true

require "spec_helper"

describe Badline::Drive1581::WD1772 do
  subject(:fdc) { described_class.new(mechanism) }

  let(:mechanism) { Badline::Drive1581::Mechanism.new }
  let(:disk) { Badline::Drive1581::Disk.new }
  let(:busy) { described_class::BUSY }
  let(:revolution) { Badline::Drive1581::Mechanism::REVOLUTION }

  # Sector n of each standard track holds n, its cylinder and its side,
  # then the byte's place.
  def format(cylinders = 0..9)
    cylinders.each do |cylinder|
      2.times do |side|
        track = Badline::Drive1581::Track.standard(cylinder, side) do |sector|
          [sector, cylinder, side, *Array.new(509) { |i| i & 0xff }]
        end
        disk.write(cylinder, side, track)
      end
    end
  end

  def spin
    mechanism.insert(disk, fdc.now)
    mechanism.motor(true, fdc.now)
    fdc.spin_changed
  end

  def command(value)
    fdc.poke(0, value)
  end

  def run(cycles) = cycles.times { fdc.cycle! }

  # Runs until the command ends, a phase at a time, reading the data
  # register at each DRQ. Returns the bytes read.
  def read_all(limit = 3_000_000, chip: fdc)
    bytes = []
    while chip.now < limit
      chip.fast_forward(chip.quiet_cycles)
      chip.cycle!
      bytes << chip.peek(3) if chip.drq?
      return bytes unless chip.busy?
    end
    bytes
  end

  # Runs until the command ends, a phase at a time, handing it +bytes+ at
  # each DRQ.
  def write_all(bytes, limit = 3_000_000)
    queue = bytes.dup
    while fdc.now < limit
      fdc.fast_forward(fdc.quiet_cycles)
      fdc.cycle!
      fdc.poke(3, queue.shift || 0) if fdc.drq?
      return unless fdc.busy?
    end
  end

  # Runs until the command ends, a phase at a time, and returns the
  # cycle it ended on.
  def finish(limit = 5_000_000)
    while fdc.now < limit
      fdc.fast_forward(fdc.quiet_cycles)
      fdc.cycle!
      return fdc.now unless fdc.busy?
    end
  end

  # The cycles at which the next +count+ DRQs come, read as they do.
  def drq_times(count)
    times = []
    until times.length == count
      fdc.cycle!
      next unless fdc.drq?

      fdc.peek(3)
      times << fdc.now
    end
    times
  end

  def snapshot
    out = Badline::Snapshot::StateWriter.new
    fdc.save_state(out)
    described_class.new(mechanism).tap { |copy| copy.load_state(Badline::Snapshot::StateReader.new(out.state)) }
  end

  def seek(cylinder)
    fdc.poke(3, cylinder)
    command(0x1a)
    finish
  end

  before do
    format
    spin
  end

  describe "the registers" do
    it "starts with 1 in the sector register" do
      expect(fdc.peek(2)).to eq(1)
    end

    it "keeps a track written to the track register" do
      fdc.poke(1, 0x22)
      expect(fdc.peek(1)).to eq(0x22)
    end

    it "ignores writes to the sector register while busy" do
      command(0x48)
      fdc.poke(2, 9)
      expect(fdc.peek(2)).to eq(1)
    end

    it "sets BUSY as the command is written" do
      command(0x0a)
      expect(fdc.status & busy).to eq(busy)
    end

    it "takes the command up 32 cycles later" do
      command(0x0a)
      expect(finish).to eq(described_class::START)
    end
  end

  describe "type I" do
    it "reports track 0 with the head on it" do
      expect(fdc.status & described_class::TRACK0).to eq(described_class::TRACK0)
    end

    it "seeks the head to the data register's track" do
      seek(7)
      expect([mechanism.cylinder, fdc.peek(1)]).to eq([7, 7])
    end

    it "waits out the step rate rr picks between steps" do
      fdc.poke(3, 3)
      command(0x1a)
      expect(finish).to eq(described_class::START + (3 * 4_000))
    end

    it "steps the 1772's 12 ms with rr = 01" do
      command(0x49)
      expect(finish).to eq(described_class::START + 24_000)
    end

    it "restores the head to track 0" do
      seek(5)
      command(0x0a)
      finish
      expect([mechanism.cylinder, fdc.peek(1)]).to eq([0, 0])
    end

    it "updates the track register on a step with u" do
      command(0x5a)
      finish
      expect(fdc.peek(1)).to eq(1)
    end

    it "leaves the track register alone on a step without u" do
      command(0x4a)
      finish
      expect([mechanism.cylinder, fdc.peek(1)]).to eq([1, 0])
    end

    it "steps the way the last step went" do
      seek(4)
      command(0x3a)
      finish
      expect(mechanism.cylinder).to eq(5)
    end

    it "steps out" do
      seek(4)
      command(0x7a)
      finish
      expect(fdc.peek(1)).to eq(3)
    end

    it "settles and finds the track with V" do
      fdc.poke(3, 2)
      command(0x1e)
      finish
      expect(fdc.status & described_class::NOT_FOUND).to eq(0)
    end

    it "gives up on a track it can't find after five turns with V" do
      fdc.poke(3, 20)
      command(0x1e)
      expect(finish).to be > 4 * revolution
    end

    it "reports the index pulse as the disk turns" do
      run(revolution - fdc.now)
      expect(fdc.status & described_class::INDEX).to eq(described_class::INDEX)
    end
  end

  describe "read sector" do
    def read(sector, track: 0)
      fdc.poke(1, track)
      fdc.poke(2, sector)
      command(0x88)
      read_all
    end

    it "reads the sector's 512 bytes" do
      expect(read(3)[0, 4]).to eq([3, 0, 0, 0])
    end

    it "reads every byte" do
      expect(read(3).length).to eq(512)
    end

    it "reads from the side under the head" do
      mechanism.side = 1
      expect(read(4)[0, 3]).to eq([4, 0, 1])
    end

    it "moves a byte every 64 cycles" do
      fdc.poke(2, 1)
      command(0x88)
      expect(drq_times(3).each_cons(2).map { |a, b| b - a }).to eq([64, 64])
    end

    it "gives up after five index pulses on a sector that isn't there" do
      read(11)
      expect(fdc.status & described_class::NOT_FOUND).to eq(described_class::NOT_FOUND)
    end

    it "looks for the track register's track in the ID" do
      read(1, track: 5)
      expect(fdc.status & described_class::NOT_FOUND).to eq(described_class::NOT_FOUND)
    end

    it "reports lost data when the bytes go unread" do
      fdc.poke(2, 2)
      command(0x88)
      finish
      expect(fdc.status & described_class::LOST_DATA).to eq(described_class::LOST_DATA)
    end

    it "reports a data field whose CRC doesn't read back" do
      disk.track(0, 0).sectors[1].data.good = false
      read(2)
      expect(fdc.status & described_class::CRC_ERROR).to eq(described_class::CRC_ERROR)
    end

    it "reports a deleted data mark" do
      disk.track(0, 0).sectors[1].data.deleted = true
      read(2)
      expect(fdc.status & described_class::DELETED).to eq(described_class::DELETED)
    end

    it "goes on to the next sectors with m" do
      fdc.poke(2, 9)
      command(0x98)
      expect(read_all(5_000_000).each_slice(512).map(&:first)).to eq([9, 10])
    end
  end

  describe "read address" do
    let!(:bytes) do
      command(0xc8)
      read_all
    end

    it "reads the next ID's four bytes and its CRC" do
      expect(bytes).to eq([0, 0, 1, 2, *Badline::Drive1581::Track.field_crc(0xfe, [0, 0, 1, 2])])
    end

    it "copies the track into the sector register" do
      expect(fdc.peek(2)).to eq(0)
    end
  end

  describe "write sector" do
    def write(sector, byte)
      fdc.poke(2, sector)
      command(0xaa)
      write_all(Array.new(512, byte))
    end

    it "writes the data field" do
      write(5, 0x6c)
      expect(disk.track(0, 0).sectors[4].data.bytes.uniq).to eq([0x6c])
    end

    it "notes the track written" do
      write(5, 0x6c)
      expect(disk).to be_written
    end

    it "writes a deleted data mark with a" do
      fdc.poke(2, 5)
      command(0xab)
      write_all([])
      expect(disk.track(0, 0).sectors[4].data.deleted).to be(true)
    end

    it "gives up with lost data when the first byte doesn't come" do
      fdc.poke(2, 5)
      command(0xaa)
      finish
      expect(fdc.status & described_class::LOST_DATA).to eq(described_class::LOST_DATA)
    end

    it "refuses a write-protected disk" do
      disk.opened("disk.d81", true)
      write(5, 0x6c)
      expect(fdc.status & described_class::PROTECTED).to eq(described_class::PROTECTED)
    end
  end

  describe "write track" do
    # The bytes the DOS's format sends for one sector of cylinder 0, side
    # 0, after the index gap.
    def format_bytes(sector)
      [*Array.new(32, 0x4e), *Array.new(12, 0), 0xf5, 0xf5, 0xf5, 0xfe, 0, 0, sector, 2, 0xf7,
       *Array.new(22, 0x4e), *Array.new(12, 0), 0xf5, 0xf5, 0xf5, 0xfb, *Array.new(512, 0xe5), 0xf7]
    end

    before do
      command(0xfa)
      write_all(format_bytes(7))
    end

    it "lays down the fields the CPU sends" do
      expect(disk.track(0, 0).sectors.map { |sector| sector.id.bytes }).to eq([[0, 0, 7, 2]])
    end

    it "writes their CRCs" do
      expect(disk.track(0, 0).sectors.first.data.good).to be(true)
    end

    it "reads back with read sector" do
      fdc.poke(2, 7)
      command(0x88)
      expect(read_all.uniq).to eq([0xe5])
    end
  end

  describe "read track" do
    it "reads a whole turn from the index" do
      command(0xe8)
      expect(read_all.length).to eq(6250)
    end
  end

  describe "force interrupt" do
    it "stops the command running" do
      fdc.poke(2, 3)
      command(0x88)
      run(1000)
      command(0xd0)
      expect(fdc.busy?).to be(false)
    end

    it "interrupts at once with I3" do
      command(0xd8)
      expect(fdc.intrq?).to be(true)
    end

    it "switches the status to type I" do
      fdc.poke(2, 30)
      command(0x88)
      finish
      command(0xd0)
      expect(fdc.status & described_class::TRACK0).to eq(described_class::TRACK0)
    end
  end

  describe "the motor" do
    it "turns on with a command" do
      command(0x0a)
      run(described_class::START)
      expect(fdc.status & described_class::MOTOR_ON).to eq(described_class::MOTOR_ON)
    end

    it "turns off after nine idle turns" do
      command(0x0a)
      finish
      9.times { finish(fdc.now + revolution + 1) }
      expect(fdc.motor_on?).to be(false)
    end

    it "waits six index pulses to spin up with h clear" do
      command(0x02)
      expect(finish).to be > 5 * revolution
    end

    it "reports the spin-up done" do
      command(0x02)
      finish
      expect(fdc.status & described_class::SPUN_UP).to eq(described_class::SPUN_UP)
    end
  end

  describe "fast_forward" do
    it "leaves room up to the next phase" do
      command(0x49)
      run(described_class::START)
      expect(fdc.quiet_cycles).to eq(24_000 - 1)
    end

    it "lands where cycling would" do
      command(0x49)
      run(described_class::START)
      fdc.fast_forward(fdc.quiet_cycles)
      fdc.cycle!
      expect(fdc.busy?).to be(false)
    end
  end

  describe "a snapshot" do
    it "carries a read on from the byte it was at" do
      fdc.poke(2, 6)
      command(0x88)
      read_all(fdc.now + 200_000)
      copy = snapshot
      expect(read_all(chip: copy)).to eq(read_all)
    end

    it "fits a native build's integers with nothing due" do
      out = Badline::Snapshot::StateWriter.new
      fdc.save_state(out)
      expect { Badline::Snapshot::MachineState.encode(out.state) }.not_to raise_error
    end
  end
end
