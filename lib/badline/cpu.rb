# frozen_string_literal: true

require "badline/cpu/microcode"
require "badline/cpu/addressing"
require "badline/cpu/operations"
require "badline/cpu/stack_operations"

module Badline
  # A cycle-stepped 6502. Every opcode decodes to a plan naming the
  # micro-operation that runs on each of its cycles, so a cycle is one
  # table lookup and one dispatch rather than a coroutine switch.
  class CPU
    STATUS_FLAGS = [:carry, :zero, :interrupt, :decimal, :break, 1,
                    :overflow, :negative].freeze

    include IntegerHelper
    include InstructionSet
    include Interrupts
    include Traps
    include Addressing
    include Operations
    include StackOperations

    attr_reader :memory, :instructions, :boundary_crossed, :cycles
    attr_accessor :program_counter, :stack_pointer, :status, :a, :x, :y,
                  :nmi, :irq

    def initialize(memory = nil, debug: false)
      @debug = debug
      @memory = memory || Memory.new
      @status = Status.new(STATUS_FLAGS, value: 0b00100000)
      reset_registers

      @nmi = @irq = false
      @irq_sample = @irq_pending = false
      @nmi_sample = @nmi_pending = false
      @skip_poll = false
      @boundary_crossed = false
      @interrupt = nil
      @brk = false
      @pending_write = false

      @cycles = 0
      @instructions = 0
      @traps = nil
      end_sequence
    end

    def reset!
      status.interrupt = true
      reset_registers
    end

    def p
      status.value
    end

    def p=(new_value)
      status.value = new_value
    end

    # Runs one cycle: the interrupt poll, the micro-operation scheduled for
    # it, and the announcement of whether the next one drives a write.
    def cycle!
      poll
      index = @index
      @index = index + 1
      send(@plan[index])
      @cycles += 1
      @pending_write = @writes[@index]
      nil
    end

    def pending_write?
      @pending_write
    end

    def step!
      cycle!
      cycle! until @plan.equal?(FETCH_PLAN)
      nil
    end

    def inspect
      "Cycles: #{@cycles}, PC: #{format16(program_counter)}, " \
        "SP: #{format8(stack_pointer)}, A: #{format8(a)}, X: #{format8(x)}, " \
        "Y: #{format8(y)}, P: #{format8(p)}"
    end

    private

    # The instruction boundary. It either commits the interrupt sampled on
    # the second-to-last cycle of the instruction that just ended, or
    # decodes the next opcode and loads its plan.
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

    # Parks the sequencer back on the opcode fetch and latches the
    # interrupt state the boundary will act on.
    def end_sequence
      @plan = FETCH_PLAN
      @writes = FETCH_WRITES
      @index = 0
      @boundary_irq = @irq_pending
      @boundary_nmi = @nmi_pending
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
