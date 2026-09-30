# frozen_string_literal: true

require "badline/cpu/microcode"
require "badline/cpu/addressing"
require "badline/cpu/operations"
require "badline/cpu/stack_operations"
require "badline/cpu/boundary"
require "badline/cpu/saved_state"

module Badline
  class CPU
    STATUS_FLAGS = [:carry, :zero, :interrupt, :decimal, :break, 1, :overflow, :negative].freeze

    # The 6502 core, on whatever bus +memory+ is. The C64's 6510 (CPU) and
    # the 1541's 6502 (Drive1541::CPU) each include it.
    module Core
      include IntegerHelper
      include InstructionSet
      include Interrupts
      include Traps
      include Addressing
      include Operations
      include StackOperations
      include Boundary
      include SavedState

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

      def inspect
        "Cycles: #{@cycles}, PC: #{format16(program_counter)}, " \
          "SP: #{format8(stack_pointer)}, A: #{format8(a)}, X: #{format8(x)}, " \
          "Y: #{format8(y)}, P: #{format8(p)}"
      end

      private

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
    end
  end
end
