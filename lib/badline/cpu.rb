# frozen_string_literal: true

require "badline/cpu/microcode"
require "badline/cpu/addressing"
require "badline/cpu/operations"
require "badline/cpu/stack_operations"

module Badline
  class CPU
    STATUS_FLAGS = [:carry, :zero, :interrupt, :decimal, :break, 1, :overflow, :negative].freeze

    include IntegerHelper
    include InstructionSet
    include Interrupts
    include Traps
    include Addressing
    include Operations
    include StackOperations

    attr_reader :memory, :instructions, :boundary_crossed, :cycles, :pending_write
    attr_accessor :program_counter, :stack_pointer, :status, :a, :x, :y, :nmi, :irq

    alias pending_write? pending_write

    # +ane_constant+ is ANE's magic constant, which varies from chip to
    # chip. The default is the C64 6510's.
    def initialize(memory, debug: false, ane_constant: 0xef)
      @debug = debug
      @ane_constant = ane_constant
      @memory = memory
      @status = CPUStatus.new(STATUS_FLAGS, value: 0b00100000)
      reset_registers

      @nmi = @irq = false
      @irq_sample = @irq_pending = false
      @nmi_sample = @nmi_pending = false
      @skip_poll = false
      @boundary_crossed = false
      @interrupt = nil
      @brk = false
      @pending_write = false
      @stalled_at = nil
      @so_high = true

      @cycles = 0
      @instructions = 0
      @traps = nil
      end_sequence
    end

    def reset!
      status.interrupt = true
      reset_registers
      @nmi = false
      @irq_sample = @irq_pending = false
      @nmi_sample = @nmi_pending = false
      @skip_poll = false
      @pending_write = false
      end_sequence
    end

    def p
      status.value
    end

    def p=(new_value)
      status.value = new_value
    end

    def cycle!
      poll # the interrupt lines

      # Run the next step
      index = @index
      @index = index + 1
      send(@plan[index])
      @cycles += 1

      # Record if the next step writes to memory
      @pending_write = @writes[@index]
      nil
    end

    # Called instead of #cycle! on a cycle the VIC holds the CPU through
    # BA. Records which cycle the CPU was stalled before, and keeps
    # sampling the interrupt lines.
    def stall!
      @stalled_at = @cycles
      sample_while_stalled
    end

    # The 6502's SO (set overflow) pin, which the 6510 leaves out, so the
    # C64 never drives it. A falling edge sets V and a held level does
    # nothing more.
    def so=(high)
      @status.overflow = true if @so_high && !high
      @so_high = high
    end

    # Pulses SO: pulls it low, which sets V, and releases it.
    def so!
      @status.overflow = true
      @so_high = true
    end

    def jammed?
      @plan.equal?(JAMMED_PLAN)
    end

    # Runs to the end of the instruction, or until the CPU jams.
    def step!
      cycle!
      cycle! until @plan.equal?(FETCH_PLAN) || jammed?
      nil
    end

    # Whether the next cycle fetches an opcode.
    def boundary? = @index.zero? && @plan.equal?(FETCH_PLAN)

    def trapped? = !@traps.nil?

    # Everything the CPU holds but its cycle and instruction counts: the
    # registers, the interrupt lines and pipeline, and what the last
    # instruction left in its working registers. Drive1541::Idle compares
    # it at two instruction boundaries.
    def idle_state
      [@program_counter, @stack_pointer, @a, @x, @y, @status.value,
       @irq, @nmi, @irq_sample, @irq_pending, @nmi_sample, @nmi_pending, @skip_poll,
       @boundary_irq, @boundary_nmi, @so_high, @interrupt, @brk, @pending_write, @stalled_at, @traps,
       @operation, @optional_dummy, @boundary_crossed, @branch_taken,
       @address, @pointer, @dummy_address, @value, @rmw_result]
    end

    # Counts +cycles+ cycles and +instructions+ instructions that ran
    # without changing anything idle_state holds.
    def fast_forward(cycles, instructions)
      @cycles += cycles
      @instructions += instructions
    end

    def inspect
      "Cycles: #{@cycles}, PC: #{format16(program_counter)}, " \
        "SP: #{format8(stack_pointer)}, A: #{format8(a)}, X: #{format8(x)}, " \
        "Y: #{format8(y)}, P: #{format8(p)}"
    end

    private

    # The first cycle of every instruction. Starts an interrupt if one was
    # pending when the previous instruction ended. Otherwise reads the
    # opcode and switches to its plan.
    def op_fetch
      return start_interrupt if @boundary_nmi || @boundary_irq

      run_traps
      opcode = @memory.peek(@program_counter)
      log(opcode) if @debug
      micro = MICROCODE[opcode]
      @operation = micro.operation
      @plan = micro.plan
      @writes = micro.writes
      @optional_dummy = micro.optional_dummy
      @index = 1
      @boundary_crossed = false
      @program_counter = (@program_counter + 1) & 0xffff
    end

    def end_instruction
      @instructions += 1
      end_sequence
    end

    # Makes the next cycle an opcode fetch, and saves the pending interrupt
    # flags for op_fetch. The next cycle polls before op_fetch runs, which
    # updates the live flags.
    def end_sequence
      @plan = FETCH_PLAN
      @writes = FETCH_WRITES
      @index = 0
      @boundary_irq = @irq_pending
      @boundary_nmi = @nmi_pending
    end

    # True when the CPU was stalled right before this cycle.
    def stalled_before_this_cycle?
      @stalled_at == @cycles
    end

    # True when the CPU was stalled right before the cycle that preceded
    # this one.
    def stalled_before_previous_cycle?
      @stalled_at == @cycles - 1
    end

    def write_byte(addr, value)
      @memory.poke(addr, value)
    end

    def stack_address(offset = 0)
      0x0100 | ((@stack_pointer + offset) & 0xff)
    end

    def reset_registers
      # The program counter is initialized from the reset vector
      @program_counter = @memory.peek16(0xfffc)
      # Stack pointer starts at 0x01ff and grows down
      @stack_pointer = 0xff
      @a = @x = @y = 0x0
    end

    def log(opcode)
      instruction = Instruction.find(opcode)
      puts(
        "#{@cycles}: PC: #{format16(@program_counter)} - " \
        "#{instruction.name.upcase} #{instruction.addressing_mode}"
      )
    end
  end
end
