# frozen_string_literal: true

require "spec_helper"
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
      expect(drive.via1.peek(0x1800)).to eq(0x1a)
    end

    it "reads the jumpers for device 9" do
      drive = described_class.new(rom: Drive1541ROM.stub, device: 9)
      expect(drive.via1.peek(0x1800) & 0x60).to eq(0x20)
    end
  end

  describe "the SO pin" do
    before do
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
end
