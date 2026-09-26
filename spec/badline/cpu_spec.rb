# frozen_string_literal: true

require "spec_helper"

describe Badline::CPU do
  let(:start_addr) { 0xc000 }
  let(:memory) do
    Badline::Memory.new.tap do |m|
      m.poke(0xfffc, start_addr)
    end
  end
  let(:cpu) { described_class.new(memory) }

  def execute(bytes, steps = 1)
    memory.write(start_addr, bytes)
    steps.times { cpu.step! }
  end

  describe "Non-maskable interrupt" do
    before do
      memory.write(0xfffa, [0x39, 0x05])
      memory.write(start_addr, [0x69, 0x05])
      cpu.nmi = true # Assert before the second-to-last cycle
      cpu.cycle!
      2.times { cpu.step! } # Finish the instruction and perform the interrupt
    end

    specify { expect(cpu.cycles).to eq(2 + 7) }
    specify { expect(cpu.stack_pointer).to eq(0xfc) }
    specify { expect(cpu.status.interrupt?).to be(true) }
    specify { expect(cpu.nmi).to be(false) }
    specify { expect(cpu.program_counter).to eq(0x0539) }

    it "finishes the previous instruction" do
      expect(cpu.a).to eq(0x05)
    end
  end

  describe "Interrupt request" do
    let(:interrupt) { false }

    before do
      memory.write(0xfffe, [0x40, 0x05])
      memory.write(start_addr, [0x69, 0x05])
      cpu.status.interrupt = interrupt
      cpu.irq = true # Assert before the second-to-last cycle
      cpu.cycle!
    end

    context "when the interrupt flag is clear" do
      before { 2.times { cpu.step! } } # Finish the instruction, take the IRQ

      specify { expect(cpu.cycles).to eq(2 + 7) }
      specify { expect(cpu.stack_pointer).to eq(0xfc) }
      specify { expect(cpu.status.interrupt?).to be(true) }
      specify { expect(cpu.program_counter).to eq(0x0540) }

      it "finishes the previous instruction" do
        expect(cpu.a).to eq(0x05)
      end
    end

    context "when the interrupt flag is set" do
      let(:interrupt) { true }

      before { cpu.step! } # Finish the instruction; the masked IRQ is ignored

      specify { expect(cpu.cycles).to eq(2) }
      specify { expect(cpu.stack_pointer).to eq(0xff) }
      specify { expect(cpu.program_counter).to eq(0xc002) }

      # The line stays asserted while masked; it is serviced once I clears.
      specify { expect(cpu.irq).to be(true) }
    end
  end

  # Pinned by Lorenz irq/nmi
  describe "interrupt recognition timing" do
    before do
      memory.write(0xfffa, [0x39, 0x05])
      memory.write(0xfffe, [0x40, 0x05])
    end

    context "when the IRQ rises on an instruction's final cycle" do
      before do
        memory.write(start_addr, [0xe8, 0xe8, 0xe8])
        cpu.cycle! # INX cycle 1
        cpu.irq = true
        3.times { cpu.step! }
      end

      it "executes one more instruction before the handler" do
        expect(cpu.x).to eq(2)
      end

      specify { expect(cpu.program_counter).to eq(0x0540) }
    end

    context "when the IRQ rises during a taken same-page branch" do
      before do
        memory.write(start_addr, [0xd0, 0x02, 0xea, 0xea, 0xe8])
        cpu.cycle! # BNE cycle 1
        cpu.irq = true
        3.times { cpu.step! }
      end

      it "executes the next instruction before the handler" do
        expect(cpu.x).to eq(1)
      end

      specify { expect(cpu.program_counter).to eq(0x0540) }
    end

    context "when the IRQ rises during a taken page-crossing branch" do
      let(:start_addr) { 0xc0fd }

      before do
        memory.write(start_addr, [0xd0, 0x02, 0xea, 0xea, 0xe8])
        cpu.cycle! # BNE cycle 1
        cpu.irq = true
        2.times { cpu.step! }
      end

      it "enters the handler without running the next instruction" do
        expect(cpu.x).to eq(0)
      end

      specify { expect(cpu.program_counter).to eq(0x0540) }
    end

    context "when CLI unmasks a pending IRQ" do
      before do
        cpu.status.interrupt = true
        cpu.irq = true
        memory.write(start_addr, [0x58, 0xe8, 0xe8])
        3.times { cpu.step! }
      end

      it "executes one instruction after CLI before the handler" do
        expect(cpu.x).to eq(1)
      end

      specify { expect(cpu.program_counter).to eq(0x0540) }
    end

    context "when SEI executes with an IRQ pending" do
      before do
        cpu.irq = true
        memory.write(start_addr, [0x78])
        2.times { cpu.step! }
      end

      specify { expect(cpu.program_counter).to eq(0x0540) }

      it "pushes the status with the interrupt flag set" do
        expect(memory.peek(0x01fd) & 0x04).to eq(0x04)
      end
    end

    context "when an NMI rises before cycle 4 of a BRK" do
      before do
        memory.write(start_addr, [0x00])
        cpu.cycle! # BRK cycle 1
        cpu.nmi = true
        cpu.step!
      end

      it "finishes the BRK as an NMI" do
        expect(cpu.program_counter).to eq(0x0539)
      end

      it "keeps the break flag set on the stack" do
        expect(memory.peek(0x01fd) & 0x10).to eq(0x10)
      end

      specify { expect(cpu.nmi).to be(false) }
    end

    context "when an NMI rises after the BRK hijack window" do
      before do
        memory.write(0x0540, [0xe8])
        memory.write(start_addr, [0x00])
        5.times { cpu.cycle! } # BRK cycles 1-5
        cpu.nmi = true
        3.times { cpu.step! }
      end

      it "runs the handler's first instruction before the NMI" do
        expect(cpu.x).to eq(1)
      end

      specify { expect(cpu.program_counter).to eq(0x0539) }
    end

    context "when an NMI rises late in an IRQ sequence" do
      before do
        memory.write(0x0540, [0xe8])
        memory.write(start_addr, [0xea])
        cpu.irq = true
        8.times { cpu.cycle! } # NOP + IRQ sequence up to cycle 6
        cpu.nmi = true
        3.times { cpu.step! }
      end

      it "runs the handler's first instruction before the NMI" do
        expect(cpu.x).to eq(1)
      end

      specify { expect(cpu.program_counter).to eq(0x0539) }
    end
  end

  # Pinned by interrupts/irqdma and Lorenz irq/nmi
  describe "interrupts sampled while stalled by the VIC" do
    before do
      memory.write(0xfffa, [0x39, 0x05])
      memory.write(0xfffe, [0x40, 0x05])
    end

    # Runs +cycles+ cycles of the program, raises +line+, stalls the CPU
    # for one cycle, then runs +steps+ more instructions.
    def stall_after(program, cycles:, steps:, line: :irq=)
      memory.write(start_addr, program)
      cycles.times { cpu.cycle! }
      cpu.public_send(line, true) if line
      cpu.stall!
      steps.times { cpu.step! }
    end

    context "when the IRQ rises while a NOP is stalled on its last cycle" do
      before { stall_after([0xea, 0xe8], cycles: 1, steps: 2) }

      it "enters the handler right after the NOP" do
        expect(cpu.program_counter).to eq(0x0540)
      end
    end

    context "when the NMI rises while a NOP is stalled on its last cycle" do
      before { stall_after([0xea, 0xe8], cycles: 1, steps: 2, line: :nmi=) }

      it "enters the handler right after the NOP" do
        expect(cpu.program_counter).to eq(0x0539)
      end
    end

    context "when the IRQ rises while a CLI is stalled on its execute cycle" do
      before do
        cpu.status.interrupt = true
        stall_after([0x58, 0xe8], cycles: 1, steps: 2)
      end

      it "enters the handler right after the CLI" do
        expect(cpu.program_counter).to eq(0x0540)
      end
    end

    context "when the IRQ rises while an SEI is stalled on its execute cycle" do
      before { stall_after([0x78, 0xe8, 0xe8], cycles: 1, steps: 3) }

      it "masks the IRQ" do
        expect(cpu.x).to eq(2)
      end
    end

    context "when an SEI's fetch sampled the IRQ before the stall" do
      before do
        cpu.irq = true
        stall_after([0x78, 0xe8], cycles: 1, steps: 2, line: nil)
      end

      it "keeps the sample and enters the handler right after the SEI" do
        expect(cpu.program_counter).to eq(0x0540)
      end
    end

    context "when the IRQ rises while a PLP pulling I = 1 is stalled on its stack read" do
      before do
        cpu.stack_pointer = 0xfe
        memory.poke(0x01ff, 0x04)
        stall_after([0x28, 0xe8], cycles: 3, steps: 2)
      end

      it "masks with the old I and enters the handler right after the PLP" do
        expect(cpu.program_counter).to eq(0x0540)
      end
    end

    context "when a taken same-page branch is stalled on its last cycle" do
      before do
        memory.write(start_addr, [0xd0, 0x02, 0xea, 0xea, 0xe8])
        cpu.cycle! # BNE cycle 1
        cpu.irq = true
        cpu.cycle! # BNE cycle 2
        cpu.stall!
        3.times { cpu.step! }
      end

      it "still skips the poll and executes the next instruction before the handler" do
        expect(cpu.x).to eq(1)
      end
    end
  end

  describe "#pending_write?" do
    # STA $10: fetch (read), operand (read), store (write).
    before { memory.write(start_addr, [0x85, 0x10]) }

    it "is false while a read cycle is pending" do
      cpu.cycle! # paused before the operand read
      expect(cpu.pending_write?).to be(false)
    end

    it "is true while a write cycle is pending" do
      2.times { cpu.cycle! } # paused before the store
      expect(cpu.pending_write?).to be(true)
    end

    it "clears again once the write has run" do
      3.times { cpu.cycle! } # store completed, next opcode fetch pending
      expect(cpu.pending_write?).to be(false)
    end
  end

  # Pinned by CPU/cpujam (cpujam*, jamirq, jamnmi)
  describe "JAM" do
    before do
      memory.write(0xfffa, [0x39, 0x05])
      memory.write(0xfffe, [0x40, 0x05])
      memory.write(start_addr, [0x02, 0xe8])
      cpu.step! # Stops once the CPU jams
    end

    specify { expect(cpu.cycles).to eq(5) }
    specify { expect(cpu).to be_jammed }

    context "when left running" do
      before do
        allow(memory).to receive(:peek).and_call_original
        100.times { cpu.cycle! }
      end

      specify { expect(cpu).to be_jammed }
      specify { expect(cpu.program_counter).to eq(start_addr + 1) }
      specify { expect(cpu.pending_write?).to be(false) }

      it "reads $FFFF on every cycle" do
        expect(memory).to have_received(:peek).with(0xffff).exactly(100).times
      end
    end

    context "with an IRQ pending" do
      before do
        cpu.status.interrupt = false
        cpu.irq = true
        100.times { cpu.cycle! }
      end

      specify { expect(cpu).to be_jammed }
      specify { expect(cpu.stack_pointer).to eq(0xff) }
    end

    context "with an NMI pending" do
      before do
        cpu.nmi = true
        100.times { cpu.cycle! }
      end

      specify { expect(cpu).to be_jammed }
      specify { expect(cpu.stack_pointer).to eq(0xff) }
    end

    context "when reset" do
      before do
        memory.write(0xfffc, [0x01, 0xc0])
        cpu.reset!
        cpu.step!
      end

      specify { expect(cpu).not_to be_jammed }

      it "runs from the reset vector" do
        expect(cpu.x).to eq(1)
      end
    end
  end

  # Pinned by CPU/sha, CPU/shxy and CPU/shs (variants 2-5)
  describe "SHX stalled by the VIC" do
    before do
      cpu.x = 0xff
      cpu.y = 0x10
    end

    # SHX base,Y takes five cycles: opcode, low, high, dummy read, write.
    def run_shx(base, stall_before:)
      memory.write(start_addr, [0x9e, base & 0xff, base >> 8])
      5.times do |cycle|
        cpu.stall! if cycle == stall_before
        cpu.cycle!
      end
    end

    it "stores X & (H+1) when not stalled" do
      run_shx(0x1200, stall_before: nil)
      expect(memory.peek(0x1210)).to eq(0x13)
    end

    it "drops the & (H+1) when stalled right before the dummy read" do
      run_shx(0x1200, stall_before: 3)
      expect(memory.peek(0x1210)).to eq(0xff)
    end

    it "keeps the & (H+1) when stalled a cycle earlier" do
      run_shx(0x1200, stall_before: 2)
      expect(memory.peek(0x1210)).to eq(0x13)
    end

    it "still ANDs the high byte of a page-crossing target" do
      run_shx(0x12f8, stall_before: 3)
      expect(memory.peek(0x1308)).to eq(0xff)
    end
  end

  # Pinned by CPU/ane (the constant); the stall variant follows VICE
  describe "ANE" do
    before do
      cpu.a = 0x00
      cpu.x = 0xff
      memory.write(start_addr, [0x8b, 0xff])
    end

    it "ORs A with the 6510's magic constant" do
      cpu.step!
      expect(cpu.a).to eq(0xef)
    end

    it "clears bits 0 and 4 of the constant when stalled before the operand" do
      cpu.cycle!
      cpu.stall!
      cpu.cycle!
      expect(cpu.a).to eq(0xee)
    end

    context "with another chip's constant" do
      let(:cpu) { described_class.new(memory, ane_constant: 0xee) }

      it "uses that constant" do
        cpu.step!
        expect(cpu.a).to eq(0xee)
      end
    end
  end

  describe "ADC" do
    before { cpu.a = 0x01 }

    describe "adding a value" do
      before { execute([0x69, 0x01]) }

      specify { expect(cpu.a).to eq(0x02) }
      specify { expect(cpu.status.carry?).to be(false) }
      specify { expect(cpu.status.overflow?).to be(false) }
      specify { expect(cpu.cycles).to eq(2) }
    end

    describe "when the carry bit is set" do
      before do
        cpu.status.carry = true
        execute([0x69, 0x01])
      end

      specify { expect(cpu.a).to eq(0x03) }
      specify { expect(cpu.status.carry?).to be(false) }
      specify { expect(cpu.status.overflow?).to be(false) }
    end

    describe "rolling over" do
      before do
        cpu.a = 0xff
        execute([0x69, 0x01])
      end

      specify { expect(cpu.a).to eq(0x00) }
      specify { expect(cpu.status.carry?).to be(true) }
      specify { expect(cpu.status.overflow?).to be(false) }
    end

    describe "overflowing" do
      before do
        cpu.a = -128
        execute([0x69, -1])
      end

      specify { expect(cpu.status.overflow?).to be(true) }
    end
  end

  describe "ADC (decimal mode)" do
    before do
      cpu.a = 0x22
      cpu.status.decimal = true
    end

    describe "adding a value" do
      before { execute([0x69, 0x33]) }

      specify { expect(cpu.a).to eq(0x55) }
      specify { expect(cpu.status.carry?).to be(false) }
    end

    describe "when the carry bit is set" do
      before do
        cpu.status.carry = true
        execute([0x69, 0x01])
      end

      specify { expect(cpu.a).to eq(0x24) }
      specify { expect(cpu.status.carry?).to be(false) }
    end

    describe "rolling over" do
      before do
        cpu.a = 0x99
        execute([0x69, 0x01])
      end

      specify { expect(cpu.a).to eq(0x00) }
      specify { expect(cpu.status.carry?).to be(true) }
      specify { expect(cpu.status.overflow?).to be(false) }
    end
  end

  describe "AND" do
    before do
      cpu.a = 0b00001111
      execute([0x29, 0b10101010])
    end

    specify { expect(cpu.a).to eq(0b00001010) }
    specify { expect(cpu.cycles).to eq(2) }
  end

  describe "ASL" do
    context "with accumulator addressing" do
      before do
        cpu.a = 0b11111111
        execute([0x0a])
      end

      specify { expect(cpu.a).to eq(0b11111110) }
      specify { expect(cpu.status.carry?).to be(true) }
      specify { expect(cpu.cycles).to eq(2) }
    end

    context "with carry bit" do
      before do
        cpu.status.carry = 1
        cpu.a = 0b01010101
        execute([0x0a])
      end

      specify { expect(cpu.a).to eq(0b10101010) }
      specify { expect(cpu.status.carry?).to be(false) }
    end
  end

  describe "read-modify-write memory access" do
    let(:writes) { [] }

    def run_logged(bytes)
      memory.write(start_addr, bytes)
      log = writes
      memory.define_singleton_method(:poke) do |addr, value|
        log << [addr, value]
        super(addr, value)
      end
      cpu.step!
    end

    context "with ASL absolute" do
      before do
        memory.poke(0x2000, 0b10000001)
        run_logged([0x0e, 0x00, 0x20])
      end

      it "writes the original value back before the result" do
        expect(writes).to eq([[0x2000, 0b10000001], [0x2000, 0b00000010]])
      end

      specify { expect(cpu.cycles).to eq(6) }
    end

    context "with LSR zeropage" do
      before do
        memory.poke(0x10, 0b00000011)
        run_logged([0x46, 0x10])
      end

      it "writes the original value back before the result" do
        expect(writes).to eq([[0x10, 0b00000011], [0x10, 0b00000001]])
      end

      specify { expect(cpu.cycles).to eq(5) }
    end

    context "with ROL absolute" do
      before do
        cpu.status.carry = 1
        memory.poke(0x2000, 0x80)
        run_logged([0x2e, 0x00, 0x20])
      end

      it "writes the original value back before the result" do
        expect(writes).to eq([[0x2000, 0x80], [0x2000, 0x01]])
      end
    end

    context "with ROR zeropage" do
      before do
        cpu.status.carry = 1
        memory.poke(0x10, 0x01)
        run_logged([0x66, 0x10])
      end

      it "writes the original value back before the result" do
        expect(writes).to eq([[0x10, 0x01], [0x10, 0x80]])
      end
    end

    context "with INC zeropage" do
      before do
        memory.poke(0x10, 0x41)
        run_logged([0xe6, 0x10])
      end

      it "writes the original value back before the result" do
        expect(writes).to eq([[0x10, 0x41], [0x10, 0x42]])
      end

      specify { expect(cpu.cycles).to eq(5) }
    end

    context "with DEC absolute_x" do
      before do
        cpu.x = 4
        memory.poke(0x2004, 0x10)
        run_logged([0xde, 0x00, 0x20])
      end

      it "writes the original value back before the result" do
        expect(writes).to eq([[0x2004, 0x10], [0x2004, 0x0f]])
      end

      specify { expect(cpu.cycles).to eq(7) }
    end

    context "with an illegal read-modify-write opcode (DCP zeropage)" do
      before do
        memory.poke(0x10, 0x10)
        run_logged([0xc7, 0x10])
      end

      it "writes the original value back before the result" do
        expect(writes).to eq([[0x10, 0x10], [0x10, 0x0f]])
      end

      specify { expect(cpu.cycles).to eq(5) }
    end

    context "with accumulator addressing" do
      before do
        cpu.a = 0x01
        run_logged([0x0a])
      end

      it "performs no memory writes" do
        expect(writes).to be_empty
      end

      specify { expect(cpu.cycles).to eq(2) }
    end
  end

  describe "acknowledging a VIC interrupt with ASL $D019" do
    let(:memory) do
      Badline::AddressBus.new.tap do |bus|
        bus.poke(0x00, 0x2f)
        bus.poke(0x01, 0b00000101) # HIRAM low: vectors in RAM, I/O mapped
        bus.poke16(0xfffc, start_addr)
      end
    end

    before do
      memory[0xd01a] = 0x01
      memory[0xd012] = 0x01
      130.times { memory.vic.cycle! } # Latch the raster IRQ at line 1
      memory.ram.write(start_addr, [0x0e, 0x19, 0xd0])
    end

    it "starts with the interrupt asserted" do
      expect(memory.vic.interrupted?).to be(true)
    end

    it "acknowledges the interrupt through the dummy write" do
      cpu.step!
      expect(memory.vic.interrupted?).to be(false)
    end
  end

  describe "BCC" do
    let(:carry) { false }
    let(:offset) { 0x20 }

    before do
      cpu.status.carry = carry
      execute([0x90, offset])
    end

    context "when flag is set" do
      let(:carry) { true }

      specify { expect(cpu.cycles).to eq(2) }

      specify { expect(cpu.program_counter).to eq(0xc002) }
    end

    context "when flag is clear" do
      specify { expect(cpu.cycles).to eq(3) }

      specify { expect(cpu.program_counter).to eq(0xc022) }
    end

    context "when branching across page boundary" do
      let(:offset) { -100 }

      specify { expect(cpu.program_counter).to eq(0xbf9e) }
      specify { expect(cpu.cycles).to eq(4) }
    end
  end

  describe "BCS" do
    let(:carry) { true }
    let(:offset) { 0x20 }

    before do
      cpu.status.carry = carry
      execute([0xb0, offset])
    end

    context "when flag is clear" do
      let(:carry) { false }

      specify { expect(cpu.cycles).to eq(2) }

      it "does not branch" do
        expect(cpu.program_counter).to eq(0xc002)
      end
    end

    context "when flag is set" do
      specify { expect(cpu.cycles).to eq(3) }

      it "branches" do
        expect(cpu.program_counter).to eq(0xc022)
      end
    end

    context "when branching across page boundary" do
      let(:offset) { -100 }

      it "spends an extra cycle" do
        expect(cpu.cycles).to eq(4)
      end
    end
  end

  describe "BEQ" do
    let(:zero) { true }
    let(:offset) { 0x20 }

    before do
      cpu.status.zero = zero
      execute([0xf0, offset])
    end

    context "when flag is clear" do
      let(:zero) { false }

      specify { expect(cpu.cycles).to eq(2) }

      it "does not branch" do
        expect(cpu.program_counter).to eq(0xc002)
      end
    end

    context "when flag is set" do
      specify { expect(cpu.cycles).to eq(3) }

      it "branches" do
        expect(cpu.program_counter).to eq(0xc022)
      end
    end

    context "when branching across page boundary" do
      let(:offset) { -100 }

      specify { expect(cpu.cycles).to eq(4) }
    end
  end

  describe "BIT" do
    context "when zeropage addressing" do
      before do
        memory.poke(0x20, 0b11000000)
        execute([0x24, 0x20])
      end

      specify { expect(cpu.status.negative?).to be(true) }
      specify { expect(cpu.status.overflow?).to be(true) }
      specify { expect(cpu.status.zero?).to be(true) }
      specify { expect(cpu.cycles).to eq(3) }
    end

    context "when absolute addressing" do
      before do
        cpu.a = 1
        memory.poke(0x2010, 0b00000001)
        execute([0x2c, 0x10, 0x20])
      end

      specify { expect(cpu.status.negative?).to be(false) }
      specify { expect(cpu.status.overflow?).to be(false) }
      specify { expect(cpu.status.zero?).to be(false) }
      specify { expect(cpu.cycles).to eq(4) }
    end
  end

  describe "BMI" do
    let(:negative) { true }
    let(:offset) { 0x20 }

    before do
      cpu.status.negative = negative
      execute([0x30, offset])
    end

    context "when negative is clear" do
      let(:negative) { false }

      specify { expect(cpu.cycles).to eq(2) }

      it "does not branch" do
        expect(cpu.program_counter).to eq(0xc002)
      end
    end

    context "when negative is set" do
      specify { expect(cpu.cycles).to eq(3) }

      it "branches" do
        expect(cpu.program_counter).to eq(0xc022)
      end
    end

    context "when branching across page boundary" do
      let(:offset) { -100 }

      specify { expect(cpu.cycles).to eq(4) }
    end
  end

  describe "BNE" do
    let(:zero) { false }
    let(:offset) { 0x20 }

    before do
      cpu.status.zero = zero
      execute([0xd0, offset])
    end

    context "when flag is set" do
      let(:zero) { true }

      specify { expect(cpu.cycles).to eq(2) }

      it "does not branch" do
        expect(cpu.program_counter).to eq(0xc002)
      end
    end

    context "when flag is clear" do
      specify { expect(cpu.cycles).to eq(3) }

      it "branches" do
        expect(cpu.program_counter).to eq(0xc022)
      end
    end

    context "when branching across page boundary" do
      let(:offset) { -100 }

      specify { expect(cpu.cycles).to eq(4) }
    end
  end

  describe "BPL" do
    let(:negative) { false }
    let(:offset) { 0x20 }

    before do
      cpu.status.negative = negative
      execute([0x10, offset])
    end

    context "when flag is set" do
      let(:negative) { true }

      specify { expect(cpu.cycles).to eq(2) }

      it "does not branch" do
        expect(cpu.program_counter).to eq(0xc002)
      end
    end

    context "when flag is clear" do
      specify { expect(cpu.cycles).to eq(3) }

      it "branches" do
        expect(cpu.program_counter).to eq(0xc022)
      end
    end

    context "when branching across page boundary" do
      let(:offset) { -100 }

      specify { expect(cpu.cycles).to eq(4) }
    end
  end

  describe "BRK" do
    before do
      memory.write(0xfffe, [0x40, 0x05])
      execute([0x00])
    end

    specify { expect(cpu.cycles).to eq(7) }
    specify { expect(cpu.stack_pointer).to eq(0xfc) }
    specify { expect(cpu.status.break?).to be(false) }
    specify { expect(cpu.status.interrupt?).to be(true) }
    specify { expect(cpu.irq).to be(false) }
    specify { expect(cpu.program_counter).to eq(0x0540) }
  end

  describe "BVC" do
    let(:overflow) { false }
    let(:offset) { 0x20 }

    before do
      cpu.status.overflow = overflow
      execute([0x50, offset])
    end

    context "when flag is set" do
      let(:overflow) { true }

      specify { expect(cpu.cycles).to eq(2) }

      it "does not branch" do
        expect(cpu.program_counter).to eq(0xc002)
      end
    end

    context "when flag is clear" do
      specify { expect(cpu.cycles).to eq(3) }

      it "branches" do
        expect(cpu.program_counter).to eq(0xc022)
      end
    end

    context "when branching across page boundary" do
      let(:offset) { -100 }

      it "spends an extra cycle" do
        expect(cpu.cycles).to eq(4)
      end
    end
  end

  describe "BVS" do
    let(:overflow) { true }
    let(:offset) { 0x20 }

    before do
      cpu.status.overflow = overflow
      execute([0x70, offset])
    end

    context "when flag is clear" do
      let(:overflow) { false }

      specify { expect(cpu.cycles).to eq(2) }

      it "does not branch" do
        expect(cpu.program_counter).to eq(0xc002)
      end
    end

    context "when flag is set" do
      specify { expect(cpu.cycles).to eq(3) }

      it "branches" do
        expect(cpu.program_counter).to eq(0xc022)
      end
    end

    context "when branching across page boundary" do
      let(:offset) { -100 }

      specify { expect(cpu.cycles).to eq(4) }
    end
  end

  describe "CLC" do
    before do
      cpu.status.carry = true
      execute([0x18])
    end

    specify { expect(cpu.cycles).to eq(2) }

    it "clears the flag" do
      expect(cpu.status.carry?).to be(false)
    end
  end

  describe "CLD" do
    before do
      cpu.status.decimal = true
      execute([0xd8])
    end

    specify { expect(cpu.cycles).to eq(2) }

    it "clears the flag" do
      expect(cpu.status.decimal?).to be(false)
    end
  end

  describe "CLI" do
    before do
      cpu.status.interrupt = true
      execute([0x58])
    end

    specify { expect(cpu.cycles).to eq(2) }

    it "clears the flag" do
      expect(cpu.status.interrupt?).to be(false)
    end
  end

  describe "CLV" do
    before do
      cpu.status.overflow = true
      execute([0xb8])
    end

    specify { expect(cpu.cycles).to eq(2) }

    it "clears the flag" do
      expect(cpu.status.overflow?).to be(false)
    end
  end

  describe "CMP" do
    before do
      cpu.a = 0x60
      execute([0xc9, 0x40])
    end

    specify { expect(cpu.cycles).to eq(2) }

    it "sets the flags" do
      expect(cpu.status.carry?).to be(true)
    end
  end

  describe "CPX" do
    before do
      cpu.x = 0x60
      execute([0xe0, 0x40])
    end

    specify { expect(cpu.cycles).to eq(2) }

    it "sets the flags" do
      expect(cpu.status.carry?).to be(true)
    end
  end

  describe "CPY" do
    before do
      cpu.y = 0x60
      execute([0xc0, 0x40])
    end

    specify { expect(cpu.cycles).to eq(2) }

    it "sets the flags" do
      expect(cpu.status.carry?).to be(true)
    end
  end

  describe "DEC" do
    before { memory.poke(target_addr, 0x40) }

    describe "zeropage addressing" do
      let(:target_addr) { 0x20 }

      before { execute([0xc6, target_addr]) }

      specify { expect(cpu.cycles).to eq(5) }

      it "decrements the value" do
        expect(memory.peek(target_addr)).to eq(0x3f)
      end
    end

    describe "zeropage_x addressing" do
      let(:target_addr) { 0x22 }

      before do
        cpu.x = 2
        execute([0xd6, 0x20])
      end

      specify { expect(cpu.cycles).to eq(6) }

      it "decrements the value" do
        expect(memory.peek(target_addr)).to eq(0x3f)
      end
    end

    describe "absolute addressing" do
      let(:target_addr) { 0x2010 }

      before { execute([0xce, 0x10, 0x20]) }

      specify { expect(cpu.cycles).to eq(6) }

      it "decrements the value" do
        expect(memory.peek(target_addr)).to eq(0x3f)
      end
    end

    describe "absolute_x addressing" do
      let(:target_addr) { 0x2012 }

      before do
        cpu.x = 2
        execute([0xde, 0x10, 0x20])
      end

      specify { expect(cpu.cycles).to eq(7) }

      it "decrements the value" do
        expect(memory.peek(target_addr)).to eq(0x3f)
      end
    end
  end

  describe "DEX" do
    before { execute([0xca]) }

    specify { expect(cpu.cycles).to eq(2) }

    it "decrements x by 1" do
      expect(cpu.x).to eq(255)
    end
  end

  describe "DEY" do
    before { execute([0x88]) }

    specify { expect(cpu.cycles).to eq(2) }

    it "decrements y by 1" do
      expect(cpu.y).to eq(255)
    end
  end

  describe "EOR" do
    before do
      cpu.a = 0b00001111
      execute([0x49, 0b10101010])
    end

    specify { expect(cpu.cycles).to eq(2) }

    it "does a bitwise AND on the accumulator" do
      expect(cpu.a).to eq(0b10100101)
    end
  end

  describe "INC" do
    before do
      memory.poke(0x20, 0x40)
      execute([0xe6, 0x20])
    end

    specify { expect(cpu.cycles).to eq(5) }

    it "increments the value" do
      expect(memory.peek(0x20)).to eq(0x41)
    end
  end

  describe "INX" do
    before { execute([0xe8]) }

    specify { expect(cpu.cycles).to eq(2) }

    it "increments x by 1" do
      expect(cpu.x).to eq(1)
    end
  end

  describe "INY" do
    before { execute([0xc8]) }

    specify { expect(cpu.cycles).to eq(2) }

    it "increments y by 1" do
      expect(cpu.y).to eq(1)
    end
  end

  describe "JMP" do
    context "when absolute addressing" do
      before { execute([0x4c, 0x39, 0x05]) }

      specify { expect(cpu.cycles).to eq(3) }

      it "updates the program counter" do
        expect(cpu.program_counter).to eq(0x0539)
      end
    end

    context "when indirect addressing" do
      before do
        memory.write(0x2120, [0x05, 0x39])
        execute([0x6c, 0x20, 0x21])
      end

      specify { expect(cpu.cycles).to eq(5) }

      it "updates the program counter" do
        expect(cpu.program_counter).to eq(0x3905)
      end
    end

    context "when indirect addressing (at page boundary)" do
      before do
        memory.write(0x2100, [0x11])
        memory.write(0x21ff, [0x05, 0x39])
        execute([0x6c, 0xff, 0x21])
      end

      specify { expect(cpu.cycles).to eq(5) }

      it "updates the program counter" do
        expect(cpu.program_counter).to eq(0x1105)
      end
    end
  end

  describe "JSR" do
    before { execute([0x20, 0x10, 0x20]) }

    specify { expect(cpu.cycles).to eq(6) }
    specify { expect(cpu.program_counter).to eq(0x2010) }
    specify { expect(memory.peek16(0x01fe)).to eq(0xc002) }
    specify { expect(cpu.stack_pointer).to eq(0xfd) }

    context "when executing inside the stack" do
      before do
        cpu.program_counter = 0x017b
        cpu.stack_pointer = 0x7d
        memory.write(0x0155, [0xad])
        memory.write(0x017b, [0x20, 0x55, 0x13])
        cpu.step!
      end

      specify { expect(cpu.program_counter).to eq(0x0155) }
      specify { expect(cpu.stack_pointer).to eq(0x7b) }
    end
  end

  describe "LDA" do
    context "when immediate addressing" do
      before { execute([0xa9, 0x40]) }

      specify { expect(cpu.cycles).to eq(2) }

      it "sets the accumulator" do
        expect(cpu.a).to eq(0x40)
      end
    end

    context "when zeropage addressing" do
      before do
        memory.write(0x20, [0x40])
        execute([0xa5, 0x20])
      end

      specify { expect(cpu.cycles).to eq(3) }

      it "sets the accumulator" do
        expect(cpu.a).to eq(0x40)
      end
    end

    context "when absolute addressing" do
      before do
        memory.write(0x2010, [0x40])
        execute([0xad, 0x10, 0x20])
      end

      specify { expect(cpu.cycles).to eq(4) }

      it "sets the accumulator" do
        expect(cpu.a).to eq(0x40)
      end
    end

    context "when absolute_x addressing" do
      before do
        cpu.x = 0x01
        memory.write(0x2011, [0x40])
        execute([0xbd, 0x10, 0x20])
      end

      specify { expect(cpu.cycles).to eq(4) }

      it "sets the accumulator" do
        expect(cpu.a).to eq(0x40)
      end
    end

    context "when absolute_x addressing at page boundary" do
      before do
        cpu.x = 0x03
        memory.write(0x2101, [0x40])
        execute([0xbd, 0xfe, 0x20])
      end

      specify { expect(cpu.cycles).to eq(5) }

      it "spends an extra cycle" do
        expect(cpu.a).to eq(0x40)
      end
    end

    context "when absolute_y addressing" do
      before do
        cpu.y = 0x03
        memory.write(0x2101, [0x40])
        execute([0xb9, 0xfe, 0x20])
      end

      specify { expect(cpu.cycles).to eq(5) }

      it "sets the accumulator" do
        expect(cpu.a).to eq(0x40)
      end
    end

    context "when indirect_x addressing" do
      before do
        cpu.x = 0x8e
        memory.write(0x5b18, [0x45])
        memory.write(0xb, [0x8a])
        memory.write(0x3e, [0x18, 0x5b])
        execute([0xa1, 0xb0, 0xa1])
      end

      specify { expect(cpu.cycles).to eq(6) }

      it "sets the accumulator" do
        expect(cpu.a).to eq(0x45)
      end
    end

    context "when indirect_y addressing" do
      before do
        cpu.y = 0x03
        memory.write(0x2113, [0x40])
        memory.write(0x05, [0x10, 0x21])
        execute([0xb1, 0x05])
      end

      specify { expect(cpu.cycles).to eq(5) }

      it "sets the accumulator" do
        expect(cpu.a).to eq(0x40)
      end
    end

    context "when indirect_y addressing at page boundary" do
      before do
        cpu.y = 219
        memory.write(0xe940, [0xc3])
        memory.write(0xe840, [0x1f])
        memory.write(0xff, [0x65])
        memory.write(0x0, [0xe8])
        execute([0xb1, 0xff, 0x87])
      end

      specify { expect(cpu.cycles).to eq(6) }

      it "sets the accumulator" do
        expect(cpu.a).to eq(0xc3)
      end
    end

    context "when zeropage_x addressing" do
      before do
        cpu.x = 0x93
        memory.write(0xc1, [0x65])
        memory.write(0x54, [0x7c])
        execute([0xb5, 0xc1, 0x5d])
      end

      it "sets the accumulator" do
        expect(cpu.a).to eq(0x7c)
      end
    end
  end

  describe "LDX" do
    before { execute([0xa2, 0x40]) }

    specify { expect(cpu.cycles).to eq(2) }

    it "sets the accumulator" do
      expect(cpu.x).to eq(0x40)
    end
  end

  describe "LDY" do
    before { execute([0xa0, 0x40]) }

    specify { expect(cpu.cycles).to eq(2) }

    it "sets the accumulator" do
      expect(cpu.y).to eq(0x40)
    end
  end

  describe "LSR" do
    context "with accumulator addressing" do
      before do
        cpu.a = 0b11111110
        execute([0x4a])
      end

      specify { expect(cpu.cycles).to eq(2) }
      specify { expect(cpu.a).to eq(0b01111111) }
      specify { expect(cpu.status.carry?).to be(false) }
    end

    context "with carry bit" do
      before do
        cpu.status.carry = 1
        cpu.a = 0b01010101
        execute([0x4a])
      end

      specify { expect(cpu.a).to eq(0b00101010) }
      specify { expect(cpu.status.carry?).to be(true) }
    end
  end

  describe "NOP" do
    before { execute([0xea]) }

    specify { expect(cpu.cycles).to eq(2) }
  end

  describe "ORA" do
    context "when immediate addressing" do
      before do
        cpu.a = 0b00001111
        execute([0x09, 0b10101010])
      end

      specify { expect(cpu.cycles).to eq(2) }

      it "does a bitwise AND on the accumulator" do
        expect(cpu.a).to eq(0b10101111)
      end
    end

    context "when zeropage addressing" do
      before do
        memory.poke(0xbd, 0b10101010)
        cpu.a = 0b00001111
        execute([0x05, 0xbd])
      end

      specify { expect(cpu.cycles).to eq(3) }

      it "does a bitwise AND on the accumulator" do
        expect(cpu.a).to eq(0b10101111)
      end
    end
  end

  describe "PHA" do
    before do
      cpu.a = 0x40
      execute([0x48])
    end

    specify { expect(cpu.cycles).to eq(3) }
    specify { expect(memory.peek(0x01ff)).to eq(0x40) }
    specify { expect(cpu.stack_pointer).to eq(0xfe) }
  end

  describe "PHP" do
    before do
      cpu.p = 0b10101010
      execute([0x08])
    end

    specify { expect(cpu.cycles).to eq(3) }
    specify { expect(memory.peek(0x01ff)).to eq(0b10111010) }
    specify { expect(cpu.stack_pointer).to eq(0xfe) }
  end

  describe "PLA" do
    before do
      memory.poke(0x01ff, 0x20)
      cpu.stack_pointer = 0xfe
      execute([0x68])
    end

    specify { expect(cpu.cycles).to eq(4) }
    specify { expect(cpu.a).to eq(0x20) }
    specify { expect(cpu.stack_pointer).to eq(0xff) }
  end

  describe "PLP" do
    before do
      memory.poke(0x01ff, 0b10101010)
      cpu.stack_pointer = 0xfe
      execute([0x28])
    end

    specify { expect(cpu.cycles).to eq(4) }
    specify { expect(cpu.p).to eq(0b10101010) }
    specify { expect(cpu.stack_pointer).to eq(0xff) }
  end

  describe "ROL" do
    context "with accumulator addressing" do
      before do
        cpu.a = 0b11111111
        execute([0x2a])
      end

      specify { expect(cpu.cycles).to eq(2) }
      specify { expect(cpu.a).to eq(0b11111110) }
      specify { expect(cpu.status.carry?).to be(true) }
    end

    context "with carry bit" do
      before do
        cpu.status.carry = 1
        cpu.a = 0b10101010
        execute([0x2a])
      end

      specify { expect(cpu.a).to eq(0b01010101) }
      specify { expect(cpu.status.carry?).to be(true) }
    end

    context "with zeropage addressing" do
      before do
        memory.poke(0x20, 0b11111111)
        execute([0x26, 0x20])
      end

      specify { expect(cpu.cycles).to eq(5) }
      specify { expect(memory.peek(0x20)).to eq(0b11111110) }
      specify { expect(cpu.status.carry?).to be(true) }
    end

    context "with absolute addressing" do
      before do
        memory.poke(0x2010, 0b01111111)
        execute([0x2e, 0x10, 0x20])
      end

      specify { expect(cpu.cycles).to eq(6) }
      specify { expect(memory.peek(0x2010)).to eq(0b11111110) }
      specify { expect(cpu.status.carry?).to be(false) }
    end

    context "with absolute_x addressing" do
      before do
        cpu.x = 2
        memory.poke(0x2012, 0b01111111)
        execute([0x3e, 0x10, 0x20])
      end

      specify { expect(cpu.cycles).to eq(7) }
      specify { expect(memory.peek(0x2012)).to eq(0b11111110) }
      specify { expect(cpu.status.carry?).to be(false) }
    end
  end

  describe "ROR" do
    context "with accumulator addressing" do
      before do
        cpu.a = 0b11111110
        execute([0x6a])
      end

      specify { expect(cpu.cycles).to eq(2) }
      specify { expect(cpu.a).to eq(0b01111111) }
      specify { expect(cpu.status.carry?).to be(false) }
    end

    context "with carry bit" do
      before do
        cpu.status.carry = 1
        cpu.a = 0b01010101
        execute([0x6a])
      end

      specify { expect(cpu.a).to eq(0b10101010) }
      specify { expect(cpu.status.carry?).to be(true) }
    end
  end

  describe "RTI" do
    before do
      memory.write(0x01fd, [0x40, 0x12, 0x20])
      cpu.stack_pointer = 0xfc
      execute([0x40])
    end

    specify { expect(cpu.p).to eq(0x60) }
    specify { expect(cpu.program_counter).to eq(0x2012) }
    specify { expect(cpu.stack_pointer).to eq(0xff) }
    specify { expect(cpu.cycles).to eq(6) }
  end

  describe "RTS" do
    before do
      memory.write(0x01fe, [0x12, 0x20])
      cpu.stack_pointer = 0xfd
      execute([0x60])
    end

    specify { expect(cpu.program_counter).to eq(0x2013) }
    specify { expect(cpu.stack_pointer).to eq(0xff) }
    specify { expect(cpu.cycles).to eq(6) }
  end

  describe "SBC" do
    describe "subtracting the values" do
      before do
        cpu.a = 0x05
        execute([0xe9, 0x01])
      end

      specify { expect(cpu.a).to eq(0x03) }
      specify { expect(cpu.status.carry?).to be(true) }
      specify { expect(cpu.status.overflow?).to be(false) }
      specify { expect(cpu.cycles).to eq(2) }
    end

    describe "including the carry bit" do
      before do
        cpu.a = 0x05
        cpu.status.carry = true
        execute([0xe9, 0x01])
      end

      specify { expect(cpu.a).to eq(0x04) }
      specify { expect(cpu.status.carry?).to be(true) }
      specify { expect(cpu.status.overflow?).to be(false) }
    end

    describe "setting the carry bit rolling over" do
      before do
        cpu.a = 0x0
        execute([0xe9, 0x01])
      end

      specify { expect(cpu.a).to eq(0xfe) }
      specify { expect(cpu.status.carry?).to be(false) }
      specify { expect(cpu.status.overflow?).to be(false) }
    end

    describe "setting the overflow bit" do
      before do
        cpu.a = -128
        execute([0xe9, 1])
      end

      specify { expect(cpu.status.overflow?).to be(true) }
    end
  end

  describe "SBC (decimal mode)" do
    before do
      cpu.a = 0x55
      cpu.status.decimal = true
    end

    describe "subtracting a value" do
      before { execute([0xe9, 0x33]) }

      specify { expect(cpu.a).to eq(0x21) }
      specify { expect(cpu.status.carry?).to be(true) }
    end

    describe "when the carry bit is set" do
      before do
        cpu.status.carry = true
        execute([0xe9, 0x01])
      end

      specify { expect(cpu.a).to eq(0x54) }
      specify { expect(cpu.status.carry?).to be(true) }
    end

    describe "rolling over" do
      before do
        cpu.a = 0x0
        execute([0xe9, 0x01])
      end

      specify { expect(cpu.a).to eq(0x98) }
      specify { expect(cpu.status.carry?).to be(false) }
      specify { expect(cpu.status.overflow?).to be(false) }
    end
  end

  describe "SEC" do
    before { execute([0x38]) }

    specify { expect(cpu.status.carry?).to be(true) }
    specify { expect(cpu.cycles).to eq(2) }
  end

  describe "SED" do
    before { execute([0xf8]) }

    specify { expect(cpu.status.decimal?).to be(true) }
    specify { expect(cpu.cycles).to eq(2) }
  end

  describe "SEI" do
    before { execute([0x78]) }

    specify { expect(cpu.status.interrupt?).to be(true) }
    specify { expect(cpu.cycles).to eq(2) }
  end

  describe "STA" do
    before do
      cpu.a = 0x40
      execute([0x8d, 0x10, 0x20])
    end

    specify { expect(memory.peek(0x2010)).to eq(0x40) }
    specify { expect(cpu.cycles).to eq(4) }
  end

  describe "STX" do
    before do
      cpu.x = 0x40
      execute([0x8e, 0x10, 0x20])
    end

    specify { expect(memory.peek(0x2010)).to eq(0x40) }
    specify { expect(cpu.cycles).to eq(4) }
  end

  describe "STY" do
    before do
      cpu.y = 0x40
      execute([0x8c, 0x10, 0x20])
    end

    specify { expect(memory.peek(0x2010)).to eq(0x40) }
    specify { expect(cpu.cycles).to eq(4) }
  end

  describe "TAX" do
    before do
      cpu.a = 0x40
      execute([0xaa])
    end

    specify { expect(cpu.cycles).to eq(2) }

    it "transfers the accumulator" do
      expect(cpu.x).to eq(0x40)
    end
  end

  describe "TAY" do
    before do
      cpu.a = 0x40
      execute([0xa8])
    end

    specify { expect(cpu.cycles).to eq(2) }

    it "transfers the accumulator" do
      expect(cpu.y).to eq(0x40)
    end
  end

  describe "TSX" do
    before do
      execute([0xba])
    end

    specify { expect(cpu.cycles).to eq(2) }

    it "transfers the stack pointer" do
      expect(cpu.x).to eq(0xff)
    end
  end

  describe "TXA" do
    before do
      cpu.x = 0x40
      execute([0x8a])
    end

    specify { expect(cpu.cycles).to eq(2) }

    it "transfers X to the accumulator" do
      expect(cpu.a).to eq(0x40)
    end
  end

  describe "TXS" do
    before do
      cpu.x = 0x40
      execute([0x9a])
    end

    specify { expect(cpu.cycles).to eq(2) }

    it "transfers X to the accumulator" do
      expect(cpu.stack_pointer).to eq(0x40)
    end
  end

  describe "TYA" do
    before do
      cpu.y = 0x40
      execute([0x98])
    end

    specify { expect(cpu.cycles).to eq(2) }

    it "transfers X to the accumulator" do
      expect(cpu.a).to eq(0x40)
    end
  end

  describe "#install_trap" do
    it "invokes the handler when execution reaches the address" do
      cpu.install_trap(start_addr) { cpu.a = 0x42 }
      execute([0xea])
      expect(cpu.a).to eq(0x42)
    end

    it "fetches the next instruction from the handler's program counter" do
      memory.write(0x2000, [0xa9, 0x07]) # LDA #$07
      cpu.install_trap(start_addr) { cpu.program_counter = 0x2000 }
      execute([0xea])
      expect(cpu.a).to eq(0x07)
    end
  end
end
