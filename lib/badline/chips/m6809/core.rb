# frozen_string_literal: true

require "badline/chips/m6809/opcodes"
require "badline/chips/m6809/registers"
require "badline/chips/m6809/bus_steps"
require "badline/chips/m6809/indexed"
require "badline/chips/m6809/stack"
require "badline/chips/m6809/interrupts"
require "badline/chips/m6809/arithmetic"
require "badline/chips/m6809/operations"
require "badline/chips/m6809/keyed_state"

module Badline
  module Chips
    class M6809
      # The Motorola 6809E, one bus cycle per #cycle!, on whatever bus +bus+
      # is. The bus answers read(address) and write(address, value). Dead
      # cycles are reads like any other, of the addresses Figure 17 of the
      # MC6809E datasheet gives them, and the cycles the CPU leaves the bus
      # alone (SYNC's, and HALT's) call nothing.
      #
      # Each instruction is a plan of steps, one a cycle, as the 6502 core
      # runs them: the opcode fetch picks an Entry, whose address steps
      # run first and whose tail follows.
      module Core
        include Registers
        include BusSteps
        include Indexed
        include Stack
        include Interrupts
        include Arithmetic
        include Operations
        include KeyedState

        attr_reader :bus, :cycles

        def initialize(bus)
          @bus = bus
          @cycles = 0
          @a = @b = @dp = 0
          @x = @y = @u = @s = @pc = 0
          @cc = IRQ_MASK | FIRQ_MASK
          @ea = @value = @post = @opcode = 0
          @group = @previous_group = GROUP_OTHER
          @alu_word = 0
          @vector = 0xfffe
          @interrupt_mask = 0
          @stack_u = false
          @operation = :none
          @page = PAGE1
          @tail = NO_TAIL
          clear_interrupts
          reset!
        end

        # RESET going high: the CPU masks FIRQ and IRQ, clears DP, disarms
        # NMI until S is loaded, and reads its vector from $FFFE.
        def reset!
          @cc |= IRQ_MASK | FIRQ_MASK
          @dp = 0
          @nmi_armed = false
          clear_interrupts
          @tail = NO_TAIL
          @plan = RESET_PLAN
          @index = 0
        end

        # Drops the instruction in flight so the next cycle fetches an
        # opcode at PC, and sets the cycle count.
        def resume(cycles)
          @cycles = cycles
          clear_interrupts
          boundary
        end

        def cycle!
          index = @index
          @index = index + 1
          send(@plan[index])
          @cycles += 1
          next_plan if @index >= @plan.length
          sample_lines
          nil
        end

        # Runs to the end of the instruction or interrupt sequence.
        def step!
          cycle!
          cycle! until boundary? || waiting?
          nil
        end

        # Whether the next cycle fetches an opcode, or takes an interrupt.
        def boundary? = @index.zero? && @plan.equal?(FETCH_PLAN)

        def inspect
          format("Cycles: %<cycles>d, PC: %<pc>04x, S: %<s>04x, U: %<u>04x, X: %<x>04x, Y: %<y>04x, " \
                 "A: %<a>02x, B: %<b>02x, DP: %<dp>02x, CC: %<cc>02x",
                 cycles: @cycles, pc: @pc, s: @s, u: @u, x: @x, y: @y, a: @a, b: @b, dp: @dp, cc: @cc)
        end

        private

        def boundary
          @plan = FETCH_PLAN
          @index = 0
          @tail = NO_TAIL
        end

        # Starts an opcode's plan after its fetch.
        def start(entry)
          @operation = entry.operation
          @previous_group = @group
          @group = entry.group
          @stack_u = false
          plan = entry.plan
          if plan.empty?
            @tail = NO_TAIL
            switch_to(entry.tail)
          else
            @tail = entry.tail
            @plan = plan
            @index = 0
          end
        end

        # Replaces the rest of the plan.
        def switch_to(plan)
          @plan = plan
          @index = 0
        end

        def next_plan
          tail = @tail
          return boundary if tail.equal?(NO_TAIL)

          @tail = NO_TAIL
          return switch_to(tail) unless tail.empty?

          execute
          boundary
        end

        # Runs the instruction method of the opcode in flight.
        def execute = send(@operation)
      end
    end
  end
end
