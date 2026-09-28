# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require_relative "../support/blank_disk"
require_relative "../support/drive1541_rom"

describe Badline::Drive1541 do
  subject(:drive) { described_class.new(rom: Drive1541ROM.stub) }

  def run(cycles) = cycles.times { drive.cycle! }

  # Puts a program at $0300, where the stub ROM's reset vector points.
  def load(bytes, at: 0x0300) = drive.ram.write(at, bytes)

  describe "the CPU" do
    it "starts from the ROM's reset vector" do
      expect(drive.cpu.program_counter).to eq(0x0300)
    end

    it "runs a program from RAM" do
      load([0xa9, 0x42, 0x85, 0x10, 0x4c, 0x04, 0x03]) # LDA #$42; STA $10; JMP *
      run(10)
      expect(drive.ram.peek(0x10)).to eq(0x42)
    end

    it "starts over from the reset vector on reset" do
      load([0x4c, 0x10, 0x03, 0x4c, 0x00, 0x05], at: 0x0310) # JMP *
      drive.cpu.program_counter = 0x0310
      run(10)
      drive.reset!
      expect(drive.cpu.program_counter).to eq(0x0300)
    end

    [["VIA 1", 0x18], ["VIA 2", 0x1c]].each do |name, page|
      it "takes an IRQ from #{name}" do
        # LDA #$C0; STA IER; LDA #$20; STA T1L-L; LDA #$00; STA T1C-H; CLI; JMP *
        load([0xa9, 0xc0, 0x8d, 0x0e, page, 0xa9, 0x20, 0x8d, 0x04, page,
              0xa9, 0x00, 0x8d, 0x05, page, 0x58, 0x4c, 0x10, 0x03])
        load([0xe6, 0x10, 0xad, 0x04, page, 0x40], at: 0x0400) # INC $10; LDA T1C-L; RTI
        run(200)
        expect(drive.ram.peek(0x10)).to eq(1)
      end
    end
  end

  describe "VIA 1's port B" do
    it "reads the serial bus released and the jumpers for device 8" do
      drive.via1.poke(0x1802, 0x1a) # DATA OUT, CLK OUT and ATNA driven low
      expect(drive.via1.peek(0x1800)).to eq(0x00)
    end

    # Undriven outputs float high into the inverters, which pull CLK and
    # DATA until the DOS sets the port up.
    it "pulls CLK and DATA from reset" do
      expect(drive.via1.peek(0x1800)).to eq(0x1f)
    end

    it "reads the jumpers for device 9" do
      drive = described_class.new(rom: Drive1541ROM.stub, device: 9)
      expect(drive.via1.peek(0x1800) & 0x60).to eq(0x20)
    end
  end

  describe "the SO pin" do
    before do
      drive.via2.poke(0x1c02, 0x04) # motor off, so no disk byte comes in
      # CLV; loop: BVC loop; LDA #$01; STA $10; JMP *
      load([0xb8, 0x50, 0xfe, 0xa9, 0x01, 0x85, 0x10, 0x4c, 0x07, 0x03])
      run(50)
    end

    it "spins in the BVC loop until a byte is ready" do
      expect(drive.ram.peek(0x10)).to eq(0)
    end

    it "leaves the loop once a byte is ready and SOE is high" do
      drive.via2.poke(0x1c0c, 0x0e) # CA2 held high
      drive.byte_ready!
      run(20)
      expect(drive.ram.peek(0x10)).to eq(1)
    end

    it "ignores a ready byte while SOE is low" do
      drive.via2.poke(0x1c0c, 0x0c) # CA2 held low
      drive.byte_ready!
      run(20)
      expect(drive.ram.peek(0x10)).to eq(0)
    end
  end

  # The DOS's way of reading a block: wait for SYNC on PB7, then take
  # each byte as BYTE READY sets V.
  describe "reading a disk" do
    include BlankDisk

    let(:disk) do
      Dir.mktmpdir do |dir|
        image = Badline::Storage::D64Image.new(blank_d64(File.join(dir, "blank.d64")))
        Badline::Drive1541::Disk.from_d64(image)
      end
    end
    let(:read) { drive.ram.read(0x0500, 10) }

    before do
      drive.insert(disk)
      load([0xa9, 0x6f, 0x8d, 0x02, 0x1c, # LDA #$6F; STA DDRB: stepper, motor, LED, rate out
            0xa9, 0xee, 0x8d, 0x0c, 0x1c, # LDA #$EE; STA PCR: CB2 read, CA2 SOE on
            0xa9, 0x01, 0x8d, 0x0b, 0x1c, # LDA #$01; STA ACR: latch port A
            0xa9, 0x4c, 0x8d, 0x00, 0x1c, # LDA #$4C; STA PB: zone 2, motor, LED, phase 0
            0x2c, 0x00, 0x1c, 0x30, 0xfb, # sync: BIT PB; BMI sync
            0xad, 0x01, 0x1c, 0xb8,       # LDA PA; CLV
            0xa0, 0x00,                   # LDY #0
            0x50, 0xfe, 0xb8,             # byte: BVC *; CLV
            0xad, 0x01, 0x1c,             # LDA PA
            0x99, 0x00, 0x05,             # STA $0500,Y
            0xc8, 0xc0, 0x0a, 0xd0, 0xf2, # INY; CPY #10; BNE byte
            0x4c, 0x2d, 0x03])            # JMP *
      run(1000)
    end

    it "reads the GCR bytes of the first header block under the head" do
      expect(read).to eq(disk.track(36).bytes[5, 10])
    end

    it "reads a header for track 18 with the disk's ID" do
      header = Badline::Drive1541::GCR.decode(read)
      expect([header[0], header[3], header[1]]).to eq([0x08, 18, header[2] ^ 18 ^ header[4] ^ header[5]])
    end
  end

  describe "#host_cycle!" do
    subject(:drive) { described_class.new(rom: Drive1541ROM.stub, host_clock_hz: 985_248) }

    before { load([0x4c, 0x00, 0x03]) } # JMP *

    def drive_cycles_per_host_cycle(drive, count)
      Array.new(count) do
        before = drive.cycles
        drive.host_cycle!
        drive.cycles - before
      end
    end

    it "runs 1 MHz against the PAL C64's 985,248 Hz" do
      30_789.times { drive.host_cycle! } # 1/32 of a second
      expect(drive.cycles).to eq(31_250)
    end

    it "runs one or two drive cycles per PAL host cycle" do
      expect(drive_cycles_per_host_cycle(drive, 1000).tally.keys.sort).to eq([1, 2])
    end

    it "runs one drive cycle per host cycle until the host sets its clock" do
      drive = described_class.new(rom: Drive1541ROM.stub)
      expect(drive_cycles_per_host_cycle(drive, 6)).to eq([1] * 6)
    end

    it "runs no drive cycle on some cycles of a faster host" do
      drive = described_class.new(rom: Drive1541ROM.stub, host_clock_hz: 2_000_000)
      expect(drive_cycles_per_host_cycle(drive, 6)).to eq([0, 1, 0, 1, 0, 1])
    end
  end

  # Runs the real DOS ROM.
  #
  # Booted to idle means both of these, after at most 3M cycles (3 s):
  # - The CPU reaches the DOS's main idle loop at $EBE7-$EC9D, which it
  #   enters once the reset routine has tested the ROM and RAM and set up
  #   both VIAs, and then spends most of its time there. The only other
  #   code it runs with nothing on the serial bus is the job loop the VIA 2
  #   timer interrupt calls, which has no jobs.
  # - The error channel holds the power-on message, "73,CBM DOS V2.6
  #   1541,00,00", which the reset routine builds in RAM on its way to the
  #   idle loop.
  describe "with the DOS ROM" do
    # One boot, about 1M drive cycles, shared by the examples: where the CPU
    # was once booted, RAM then, and whether it was in the idle loop on
    # each of the next 100,000 cycles.
    def self.boot
      @boot ||= begin
        drive = described_class.new
        in_idle_loop = -> { (0xebe7..0xec9d).cover?(drive.cpu.program_counter) }
        drive.cycle! until in_idle_loop.call || drive.cycles >= 3_000_000
        { booted_at: drive.cpu.program_counter, ram: drive.ram.read(0, 0x0800).pack("C*"),
          in_loop: Array.new(100_000) { drive.cycle! && in_idle_loop.call } }
      end
    end

    let(:idle_loop) { 0xebe7..0xec9d }
    let(:boot) { self.class.boot }

    it "reaches the idle loop" do
      expect(idle_loop).to cover(boot[:booted_at])
    end

    it "stays in the idle loop" do
      expect(boot[:in_loop].count(true)).to be > 50_000
    end

    it "has the power-on message on the error channel" do
      expect(boot[:ram]).to include("73,CBM DOS V2.6 1541,00,00")
    end
  end

  # Runs the real DOS ROM too. The C64 boots with the drive on the bus
  # and a D64 in it, and no LOAD trap: every byte comes off the disk's GCR
  # through the DOS and over the serial bus.
  describe "reading a disk with the DOS ROM" do
    include BlankDisk

    let(:computer) { Badline::Computer.new }
    let(:dir) { Dir.mktmpdir }
    let(:program) { [0x00, 0xc0, *Array.new(600) { |i| (i * 7) & 0xff }] }
    let(:output) { computer.capture_output }

    before do
      path = blank_d64(File.join(dir, "disk.d64"), name: "GCR TEST")
      give_disk_id(path)
      Badline::Storage::D64Image.new(path).write_file("data", program)
      drive = described_class.new
      drive.insert(Badline::Drive1541::Disk.from_d64(Badline::Storage::D64Image.new(path)))
      computer.attach_drive1541(drive)
      output
    end

    after { FileUtils.remove_entry(dir) }

    # The DOS copies 18/0 $A0-$AA into the directory's header line, and a
    # $00 there would end that BASIC line early.
    def give_disk_id(path)
      bytes = File.binread(path).bytes
      bytes[d64_offset(18, 0) + 0xa0, 11] = [0xa0, 0xa0, *"ID".bytes, 0xa0, *"2A".bytes, *[0xa0] * 4]
      File.binwrite(path, bytes.pack("C*"))
    end

    # Runs until BASIC has printed READY. +count+ times, or 30 s have passed.
    def run_until_ready(count)
      100_000.times { computer.cycle! } until output.output.upcase.scan("READY.").length >= count ||
                                              computer.cycles > 30_000_000
    end

    it "loads and lists the directory" do
      computer.on_init { computer.type_text("load\"$\",8\rlist\r") }
      run_until_ready(3)
      expect(output.output.upcase).to include("\"GCR TEST        \" ID 2A")
        .and include("\"DATA\"").and include("BLOCKS FREE")
    end

    it "loads a program to its own address" do
      computer.on_init { computer.type_text("load\"data\",8,1\r") }
      run_until_ready(2)
      expect(computer.ram.read(0xc000, 600)).to eq(program[2..])
    end
  end
end
