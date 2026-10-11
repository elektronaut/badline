# frozen_string_literal: true

module Badline
  class CPU
    # The CPU's state for a snapshot: the registers, the interrupt lines and
    # their pipeline, and the step of the instruction in flight, named by
    # where its plan comes from.
    module SavedState
      # Writes everything the CPU holds, down to the step of the instruction
      # it is in, for load_state to put back. The interrupt lines, BA stalls
      # and SO are state too; the traps and the debug flag belong to the host.
      def save_state(out)
        out.marker("CPU")
        out.int(@program_counter).int(@stack_pointer).int(@a).int(@x).int(@y).int(@status.value)
        [@irq, @nmi, @irq_sample, @irq_pending, @nmi_sample, @nmi_pending, @skip_poll, @boundary_irq,
         @boundary_nmi, @boundary_crossed, @brk, @pending_write, @so_high, @optional_dummy,
         @branch_taken].each { |flag| out.boolean(flag) }
        out.optional_int(@interrupt).optional_int(@stalled_at).int(@cycles).int(@instructions)
        out.int(plan_source).int(@index).int(OPERATIONS.index(@operation) || -1)
        [@address, @dummy_address, @value, @rmw_result, @pointer].each { |register| out.optional_int(register) }
      end

      def load_state(input)
        input.marker("CPU")
        @program_counter = input.int
        @stack_pointer = input.int
        @a = input.int
        @x = input.int
        @y = input.int
        @status.value = input.int
        load_flags(input)
        @interrupt = input.optional_int
        @stalled_at = input.optional_int
        @cycles = input.int
        @instructions = input.int
        load_plan(input.int)
        @index = input.int
        operation = input.int
        @operation = operation.negative? ? nil : OPERATIONS.fetch(operation)
        load_working_registers(input)
      end

      # Drops the instruction or interrupt sequence in flight and the
      # interrupt lines' pipeline, so the next cycle fetches an opcode at the
      # program counter, and sets the cycle count. A snapshot taken between
      # instructions, as VICE's are, restores through here.
      def resume(cycles)
        @irq_sample = @irq_pending = false
        @nmi_sample = @nmi_pending = false
        @skip_poll = false
        @interrupt = nil
        @brk = false
        @stalled_at = nil
        @cycles = cycles
        end_sequence
        @pending_write = false
      end

      private

      # Where the plan running comes from: an opcode's microcode, or FETCH,
      # INTERRUPT or JAMMED below it.
      def plan_source
        return FETCH if @plan.equal?(FETCH_PLAN)
        return INTERRUPT if @plan.equal?(INTERRUPT_PLAN)
        return JAMMED if @plan.equal?(JAMMED_PLAN)

        MICROCODE.index { |micro| micro.plan.equal?(@plan) && micro.operation == @operation } ||
          MICROCODE.index { |micro| micro.plan.equal?(@plan) }
      end

      def load_plan(source)
        case source
        when FETCH then use_plan(FETCH_PLAN, FETCH_WRITES)
        when INTERRUPT then use_plan(INTERRUPT_PLAN, INTERRUPT_WRITES)
        when JAMMED then use_plan(JAMMED_PLAN, JAMMED_WRITES)
        else
          micro = MICROCODE.fetch(source)
          use_plan(micro.plan, micro.writes)
        end
      end

      def use_plan(plan, writes)
        @plan = plan
        @writes = writes
      end

      def load_flags(input)
        @irq = input.boolean?
        @nmi = input.boolean?
        @irq_sample = input.boolean?
        @irq_pending = input.boolean?
        @nmi_sample = input.boolean?
        @nmi_pending = input.boolean?
        @skip_poll = input.boolean?
        @boundary_irq = input.boolean?
        @boundary_nmi = input.boolean?
        @boundary_crossed = input.boolean?
        @brk = input.boolean?
        @pending_write = input.boolean?
        @so_high = input.boolean?
        @optional_dummy = input.boolean?
        @branch_taken = input.boolean?
      end

      def load_working_registers(input)
        @address = input.optional_int
        @dummy_address = input.optional_int
        @value = input.optional_int
        @rmw_result = input.optional_int
        @pointer = input.optional_int
      end
    end
  end
end
