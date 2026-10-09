# frozen_string_literal: true

require "spec_helper"
require_relative "../support/z80_bus"

# What SingleStepTests (rake test) leaves out: reset, HALT, interrupts, R
# across prefixes, and the ED opcodes that do nothing.
describe Badline::Z80 do
  subject(:cpu) { described_class.new(bus) }

  let(:bus) { Z80Bus.new }

  # Runs +count+ steps and returns the T-states they took.
  def steps(count = 1)
    before = cpu.cycles
    count.times { cpu.step! }
    cpu.cycles - before
  end

  def enable_interrupts(mode)
    cpu.iff1 = cpu.iff2 = true
    cpu.im = mode
    cpu.sp = 0x8000
  end

  it "starts at 0 in interrupt mode 0 with interrupts disabled" do
    expect([cpu.pc, cpu.im, cpu.iff1, cpu.iff2, cpu.i, cpu.r]).to eq([0, 0, false, false, 0, 0])
  end

  it "starts again at 0 when reset" do
    enable_interrupts(2)
    cpu.pc = 0x1234
    cpu.reset!
    expect([cpu.pc, cpu.im, cpu.iff1]).to eq([0, 0, false])
  end

  it "takes 8 T-states for an ED opcode without an instruction" do
    bus.load(0, 0xed, 0x00)
    expect([steps, cpu.pc, cpu.r]).to eq([8, 2, 2])
  end

  it "uses the last of a chain of DD and FD prefixes" do
    bus.load(0, 0xdd, 0xfd, 0x21, 0x34, 0x12)
    expect([steps, cpu.iy, cpu.ix]).to eq([18, 0x1234, 0xffff])
  end

  describe "with a bus that holds WAIT" do
    before do
      allow(bus).to receive(:input) do
        cpu.wait(2)
        0xff
      end
    end

    it "lengthens the access by the wait states" do
      bus.load(0, 0xdb, 0x10)
      expect([steps, cpu.a]).to eq([13, 0xff])
    end
  end

  describe "the R register" do
    it "counts opcode fetches in its low 7 bits and keeps bit 7" do
      cpu.r = 0xff
      steps
      expect(cpu.r).to eq(0x80)
    end

    it "counts a prefix as a fetch" do
      bus.load(0, 0xdd, 0x21, 0x34, 0x12)
      steps
      expect(cpu.r).to eq(2)
    end

    it "counts DD CB as two fetches and the displacement and opcode as none" do
      bus.load(0, 0xdd, 0xcb, 0x05, 0x06)
      steps
      expect(cpu.r).to eq(2)
    end

    it "takes all 8 bits of A from LD R,A" do
      cpu.a = 0x85
      bus.load(0, 0xed, 0x4f)
      steps
      expect(cpu.r).to eq(0x85)
    end
  end

  describe "HALT" do
    before do
      bus.load(0, 0x76)
      steps
    end

    it "leaves the program counter after it" do
      steps(3)
      expect([cpu.pc, cpu.halted]).to eq([1, true])
    end

    it "fetches from there every 4 T-states and refreshes" do
      expect([steps(3), bus.accesses.last(3), cpu.r]).to eq([12, [[:fetch, 1]] * 3, 4])
    end

    it "wakes for an interrupt, which returns past it" do
      enable_interrupts(1)
      cpu.int = true
      steps
      expect([cpu.halted, cpu.pc, bus.ram[0x7ffe]]).to eq([false, 0x38, 1])
    end
  end

  describe "a maskable interrupt in mode 1" do
    before do
      bus.load(0, 0xfb, 0x00, 0x00)
      enable_interrupts(1)
      steps
      cpu.int = true
    end

    it "waits out the instruction after EI" do
      steps
      expect(cpu.pc).to eq(2)
    end

    it "then calls $0038 in 13 T-states" do
      steps
      expect([steps, cpu.pc, cpu.sp, bus.ram[0x7ffe]]).to eq([13, 0x38, 0x7ffe, 2])
    end

    it "disables interrupts and counts its acknowledge in R" do
      steps(2)
      expect([cpu.iff1, cpu.iff2, cpu.r]).to eq([false, false, 3])
    end

    it "is ignored while IFF1 is clear" do
      cpu.iff1 = false
      steps(2)
      expect(cpu.pc).to eq(3)
    end

    it "clears P/V when it follows LD A,I" do
      bus.load(1, 0xed, 0x57)
      steps
      steps
      expect(cpu.f & Badline::Z80::PF).to eq(0)
    end
  end

  describe "a maskable interrupt in mode 2" do
    before do
      enable_interrupts(2)
      cpu.i = 0x40
      bus.vector = 0x10
      bus.load(0x4010, 0x34, 0x12)
      cpu.int = true
    end

    it "calls through the vector at I and the byte on the data bus in 19 T-states" do
      expect([steps, cpu.pc, cpu.wz]).to eq([19, 0x1234, 0x1234])
    end

    it "pushes the return address before reading the vector" do
      steps
      expect(bus.accesses).to eq([[:acknowledge, nil], [:write, 0x7fff], [:write, 0x7ffe],
                                  [:read, 0x4010], [:read, 0x4011]])
    end
  end

  it "runs the RST on the data bus for a maskable interrupt in mode 0, in 13 T-states" do
    enable_interrupts(0)
    bus.vector = 0xd7
    cpu.int = true
    expect([steps, cpu.pc, bus.ram[0x7ffe]]).to eq([13, 0x10, 0])
  end

  describe "NMI" do
    before do
      enable_interrupts(1)
      cpu.nmi = true
    end

    it "calls $0066 in 11 T-states" do
      expect([steps, cpu.pc, cpu.sp]).to eq([11, 0x66, 0x7ffe])
    end

    it "clears IFF1 and leaves IFF2 for RETN" do
      steps
      expect([cpu.iff1, cpu.iff2]).to eq([false, true])
    end

    it "restores IFF1 on RETN" do
      bus.load(0x66, 0xed, 0x45)
      steps(2)
      expect([cpu.pc, cpu.iff1]).to eq([0, true])
    end

    it "is taken once while the line stays asserted" do
      steps(2)
      expect(cpu.pc).to eq(0x67)
    end

    it "comes before a maskable interrupt" do
      cpu.int = true
      steps
      expect(cpu.pc).to eq(0x66)
    end
  end
end
