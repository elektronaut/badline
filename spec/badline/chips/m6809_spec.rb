# frozen_string_literal: true

require "spec_helper"
require_relative "../../support/m6809_bus"

# What neetandev/m6809's vectors (rake test) leave out: reset, the
# interrupt lines, SYNC, CWAI, HALT, the free-running opcodes and chained
# prefixes, and the dead cycles where the core follows the MC6809E
# datasheet's Figure 17 instead of the vectors.
describe Badline::Chips::M6809 do
  subject(:cpu) { described_class.new(bus).tap { |created| bus.cpu = created } }

  let(:bus) { M6809Bus.new }

  # Puts +bytes+ at +at+ and the CPU at an instruction boundary there, with
  # S at $2000, X at $4000 and CC +cc+.
  def program(*bytes, cc: 0, at: 0x1000)
    bus.load(at, *bytes)
    cpu.pc = at
    cpu.s = 0x2000
    cpu.x = 0x4000
    cpu.cc = cc
    cpu.resume(0)
  end

  # Runs +count+ cycles, setting the lines +lines+ names for a cycle
  # before it runs.
  def cycles(count, lines = {})
    count.times do |cycle|
      lines.fetch(cycle, {}).each { |line, level| cpu.public_send("#{line}=", level) }
      cpu.cycle!
    end
  end

  def stacked(*addresses) = addresses.map { |address| format("w:%04x", address) }

  before do
    bus.load(0xfff2, 0x30, 0x00, 0x30, 0x00, 0x30, 0x00, 0x30, 0x00, 0x30, 0x00, 0x30, 0x00, 0x30, 0x00)
  end

  describe "reset" do
    # Pinned by MC6809E Fig. 6
    it "reads the vector after two dead reads of $FFFE, then a dead $FFFF" do
      bus.load(0xfffe, 0x10, 0x00)
      cycles(6)
      expect(bus.trace(0, 6)).to eq(%w[r:fffe r:fffe r:fffe r:ffff r:ffff r:1000])
    end

    it "masks FIRQ and IRQ and clears DP" do
      program(0x12)
      cpu.dp = 5
      cpu.reset!
      expect([cpu.cc, cpu.dp]).to eq([0x50, 0])
    end
  end

  describe "IRQ" do
    before { program(0x12, 0x12, 0x12) }

    # Pinned by MC6809E Fig. 8
    it "is taken once an instruction ends when it comes on the instruction's next-to-last cycle" do
      cycles(21, 0 => { irq: true })
      expect(bus.trace(2, 21)).to eq(%w[r:1001 r:1001 r:ffff] + stacked(*0x1ff4..0x1fff).reverse +
                                     %w[r:ffff r:fff8 r:fff9 r:ffff])
    end

    # Pinned by MC6809E Fig. 8
    it "waits for one more instruction when it comes on an instruction's last cycle" do
      cycles(5, 1 => { irq: true })
      expect(bus.trace(2, 5)).to eq(%w[r:1001 r:1002 r:1002])
    end

    it "stacks CC with E set and masks IRQ alone" do
      cycles(21, 0 => { irq: true })
      expect([bus.ram[0x1ff4], cpu.cc, cpu.pc]).to eq([0x80, 0x90, 0x3000])
    end

    it "is not taken while I is set" do
      cpu.cc = 0x10
      cycles(4, 0 => { irq: true })
      expect(bus.trace(2, 4)).to eq(%w[r:1001 r:1002])
    end
  end

  describe "FIRQ" do
    before { program(0x12, 0x12, cc: 0x80) }

    # Pinned by MC6809E Fig. 9
    it "stacks PC and CC in 10 cycles" do
      cycles(12, 0 => { firq: true })
      expect(bus.trace(2, 12)).to eq(%w[r:1001 r:1001 r:ffff w:1fff w:1ffe w:1ffd r:ffff r:fff6 r:fff7 r:ffff])
    end

    it "stacks CC with E clear and masks FIRQ and IRQ" do
      cycles(12, 0 => { firq: true })
      expect([bus.ram[0x1ffd], cpu.cc]).to eq([0x00, 0x50])
    end
  end

  describe "NMI" do
    it "is ignored until a program loads S after reset" do
      program(0x12, 0x12)
      cycles(4, 0 => { nmi: true })
      expect(bus.trace(2, 4)).to eq(%w[r:1001 r:1002])
    end

    it "is taken on its edge once LDS has loaded S" do
      program(0x10, 0xce, 0x20, 0x00, 0x12, 0x12)
      cycles(25, 4 => { nmi: true })
      expect(bus.trace(6, 25).values_at(0, 1, 16, 17)).to eq(%w[r:1005 r:1005 r:fffc r:fffd])
    end

    it "is taken once for an edge however long the line is held" do
      program(0x10, 0xce, 0x20, 0x00, 0x12, 0x12)
      bus.load(0x3000, 0x12, 0x12, 0x12)
      cycles(29, 4 => { nmi: true })
      expect(cpu.pc).to eq(0x3002)
    end
  end

  describe "SYNC" do
    # Pinned by MC6809E Fig. 16
    it "leaves the bus alone while it waits" do
      program(0x13, 0x12)
      cycles(6)
      expect(bus.trace(0, 6)).to eq(%w[r:1000 r:1001 - - - -])
    end

    # Pinned by MC6809E Fig. 16
    it "goes on to the next instruction a cycle after a masked interrupt wakes it" do
      program(0x13, 0x12, cc: 0x10)
      cycles(8, 4 => { irq: true })
      expect(bus.trace(4, 8)).to eq(%w[- - - r:1001])
    end

    it "takes an unmasked interrupt that wakes it" do
      program(0x13, 0x12)
      cycles(27, 4 => { irq: true })
      expect(bus.trace(7, 27).values_at(0, 1, 2, 16, 17)).to eq(%w[r:1001 r:1001 r:ffff r:fff8 r:fff9])
    end
  end

  describe "CWAI" do
    # Pinned by MC6809E Fig. 17 sheet 2
    it "stacks the entire state, then reads the vector of the interrupt it waited for, in 20 cycles" do
      program(0x3c, 0xef, 0x12, cc: 0x10)
      cycles(21, 0 => { irq: true })
      expect(bus.trace(0, 21)).to eq(%w[r:1000 r:1001 r:1002 r:ffff] + stacked(*0x1ff4..0x1fff).reverse +
                                     %w[r:ffff r:fff8 r:fff9 r:ffff r:3000])
    end

    it "reads $FFFF while it waits" do
      program(0x3c, 0xff, 0x12)
      cycles(20)
      expect(bus.trace(16, 20)).to eq(%w[r:ffff] * 4)
    end

    it "stacks CC ANDed with its operand, with E set" do
      program(0x3c, 0xef, 0x12, cc: 0x1f)
      cycles(16)
      expect(bus.ram[0x1ff4]).to eq(0x8f)
    end
  end

  describe "HALT" do
    it "stops the CPU at the next instruction boundary, off the bus" do
      program(0x12, 0x12)
      cycles(5, 0 => { halt: true })
      expect([bus.trace(0, 5), cpu.halted?]).to eq([%w[r:1000 r:1001 - - -], true])
    end

    it "lets the CPU go on once released" do
      program(0x12, 0x12)
      cycles(6, 0 => { halt: true }, 3 => { halt: false })
      expect(bus.trace(4, 6)).to eq(%w[- r:1001])
    end
  end

  it "runs free from $14 on, reading a byte a cycle" do
    program(0x14)
    cycles(4)
    expect(bus.trace(0, 4)).to eq(%w[r:1000 r:1001 r:1002 r:1003])
  end

  it "takes the first of a chain of prefixes, a cycle for each" do
    program(0x10, 0x11, 0x8e, 0x12, 0x34)
    cpu.step!
    expect([cpu.y, cpu.cycles]).to eq([0x1234, 5])
  end

  it "runs an opcode a page doesn't define as on page 1, a cycle later" do
    program(0x11, 0x86, 0x42)
    cpu.step!
    expect([cpu.a, cpu.cycles]).to eq([0x42, 3])
  end

  describe "dead cycles" do
    def run_trace(count)
      cycles(count)
      bus.trace(0, count)
    end

    # Pinned by MC6809E DEC extended example
    it "reads $FFFF between a read-modify-write's read and write" do
      program(0x7a, 0xa0, 0x00, at: 0x8000)
      expect(run_trace(7)).to eq(%w[r:8000 r:8001 r:8002 r:ffff r:a000 r:ffff w:a000])
    end

    # Pinned by MC6809E LBSR example
    it "reads the subroutine's address in LBSR" do
      program(0x17, 0x1f, 0xfd, at: 0x8000)
      cpu.s = 0xf000
      expect(run_trace(9)).to eq(%w[r:8000 r:8001 r:8002 r:ffff r:ffff r:a000 r:ffff w:efff w:effe])
    end

    # Pinned by MC6809E Fig. 17 sheet 5
    it "reads the subroutine's address in JSR" do
      program(0xbd, 0x30, 0x00)
      expect(run_trace(8)).to eq(%w[r:1000 r:1001 r:1002 r:ffff r:3000 r:ffff w:1fff w:1ffe])
    end

    # Pinned by MC6809E Fig. 17 sheet 2
    it "ends RTS on a dead read of $FFFF" do
      program(0x39)
      expect(run_trace(5)).to eq(%w[r:1000 r:1001 r:2000 r:2001 r:ffff])
    end

    # Pinned by MC6809E Fig. 17 sheet 2
    it "reads NNNN+1 after TSTA" do
      program(0x4d)
      expect(run_trace(2)).to eq(%w[r:1000 r:1001])
    end

    # Pinned by MC6809E Fig. 17 sheet 5
    it "ends SUBD on a dead read of $FFFF" do
      program(0x83, 0x12, 0x34)
      expect(run_trace(4)).to eq(%w[r:1000 r:1001 r:1002 r:ffff])
    end

    # Pinned by MC6809E Fig. 17 sheet 4
    it "follows an 8-bit index offset with a dead read of $FFFF" do
      program(0xa6, 0x88, 0x10)
      expect(run_trace(5)).to eq(%w[r:1000 r:1001 r:1002 r:ffff r:4010])
    end

    # Pinned by MC6809E Fig. 17 sheet 4
    it "reads NNNN+4 after a 16-bit index offset" do
      program(0xa6, 0x89, 0x01, 0x00)
      expect(run_trace(8)).to eq(%w[r:1000 r:1001 r:1002 r:1003 r:1004 r:ffff r:ffff r:4100])
    end
  end
end
