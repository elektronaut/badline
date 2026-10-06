# frozen_string_literal: true

require "spec_helper"
require "badline/vic20"

describe Badline::Vic20 do
  subject(:machine) { described_class.new }

  # Starts +via+'s timer 1 on a count of +count+ with its interrupt
  # enabled.
  def arm_timer(via, count)
    via.poke(0x900e, 0xc0)
    via.poke(0x9004, count)
    via.poke(0x9005, 0)
  end

  it "starts at the KERNAL's reset vector" do
    expect(machine.cpu.program_counter).to eq(0xfd22)
  end

  it "puts its VIAs in I/O 0" do
    machine.bus.poke(0x9112, 0x12)
    machine.bus.poke(0x9122, 0x22)
    expect([machine.via1.peek(0x9002), machine.via2.peek(0x9002)]).to eq([0x12, 0x22])
  end

  it "puts its VIC in I/O 0" do
    machine.bus.poke(0x900f, 0x1b)
    expect(machine.vic.peek(0x900f)).to eq(0x1b)
  end

  it "clocks the VIC with the CPU" do
    machine.run_cycles(71)
    expect(machine.vic.rasterline).to eq(1)
  end

  it "counts its cycles" do
    machine.run_cycles(1234)
    expect([machine.cycles, machine.cpu.cycles]).to eq([1234, 1234])
  end

  it "runs until the block says stop" do
    machine.run_until(10_000) { machine.cpu.program_counter == 0xfd27 }
    expect(machine.cpu.program_counter).to eq(0xfd27)
  end

  it "stops running past the limit" do
    machine.run_until(100) { false }
    expect(machine.cycles).to eq(101)
  end

  describe "the interrupt lines" do
    before { machine.cpu.p = 0x04 }

    it "takes VIA 2's interrupt on IRQ" do
      arm_timer(machine.via2, 2)
      machine.run_cycles(4)
      expect(machine.cpu.irq).to be(true)
    end

    it "leaves NMI alone on VIA 2's interrupt" do
      arm_timer(machine.via2, 2)
      machine.run_cycles(4)
      expect(machine.cpu.nmi).to be(false)
    end

    it "takes VIA 1's interrupt on NMI" do
      arm_timer(machine.via1, 2)
      machine.run_cycles(4)
      expect([machine.cpu.nmi, machine.cpu.irq]).to eq([true, false])
    end

    it "takes VIA 1's interrupt once while it stays asserted" do
      arm_timer(machine.via1, 2)
      machine.run_cycles(4)
      machine.cpu.nmi = false
      machine.run_cycles(4)
      expect(machine.cpu.nmi).to be(false)
    end
  end

  describe "#init_threshold" do
    {
      unexpanded: 700_000, "3k": 700_000, "8k": 1_350_000, "16k": 2_000_000, "24k": 2_650_000, "32k": 2_650_000,
      all: 2_650_000
    }.each do |ram, cycles|
      it "waits #{cycles} cycles with #{ram}" do
        expect(described_class.new(ram:).init_threshold).to eq(cycles)
      end
    end
  end

  describe "#on_init" do
    it "waits for the KERNAL to boot" do
      ran = false
      machine.on_init { ran = true }
      expect(ran).to be(false)
    end
  end

  it "hands over the exit code written to $910F" do
    codes = []
    machine.install_debug_register { |code| codes << code }
    machine.bus.poke(0x910f, 0x00)
    expect(codes).to eq([0x00])
  end

  it "loads a PRG at its load address" do
    address = machine.load_prg([0x01, 0x10, 0xaa, 0xbb])
    expect([address, machine.ram.peek(0x1001), machine.ram.peek(0x1002)]).to eq([0x1001, 0xaa, 0xbb])
  end

  it "shows the VIC's display" do
    expect(machine.video).to be(machine.vic)
  end

  it "shows xvic's view of the PAL frame, from line 28 on" do
    expect(machine.timing.to_h).to eq(clock_hz: 1_108_405, cycles_per_line: 71, lines_per_frame: 312,
                                      crop: [0, 28, 284, 284])
  end

  describe "#reset!" do
    before do
      machine.run_cycles(5000)
      machine.via2.poke(0x9002, 0xff)
      machine.reset!
    end

    it "sends the CPU to the reset vector" do
      expect(machine.cpu.program_counter).to eq(0xfd22)
    end

    it "resets the VIAs" do
      expect(machine.via2.peek(0x9002)).to eq(0)
    end
  end

  describe "#power_cycle!" do
    before do
      machine.ram.poke(0x1000, 0x55)
      machine.run_cycles(100)
      machine.power_cycle!
    end

    it "puts RAM back in its power-on pattern" do
      expect(machine.ram.read(0x1000, 2)).to eq([0xff, 0x00])
    end

    it "puts the raster back at the top" do
      expect([machine.vic.rasterline, machine.vic.column]).to eq([0, 0])
    end

    it "sends the CPU to the reset vector" do
      expect(machine.cpu.program_counter).to eq(0xfd22)
    end
  end
end
