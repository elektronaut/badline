# frozen_string_literal: true

module Badline
  module Chips
    class CPU
      # Where a CPU caught inside an instruction is, as a snapshot names it:
      # an opcode's instruction, an IRQ or NMI sequence, or jammed.
      POSITIONS = %w[boundary op interrupt jam].freeze

      # The CPU's fields in a keyed snapshot module (Snapshot::Keyed): the
      # registers, the interrupt lines' pipeline, the counts and, inside an
      # instruction, where it is in hardware terms (pos.*), rather than as
      # the microcode lays it out.
      module KeyedState
        def save_fields(out)
          out.int("pc", @program_counter).int("sp", @stack_pointer).int("a", @a).int("x", @x).int("y", @y)
          out.int("p", @status.value).bool("nmi", @nmi).bool("so_high", @so_high)
          out.bool("irq.sample", @irq_sample).bool("irq.pending", @irq_pending).bool("irq.boundary", @boundary_irq)
          out.bool("nmi.sample", @nmi_sample).bool("nmi.pending", @nmi_pending).bool("nmi.boundary", @boundary_nmi)
          out.bool("skip_poll", @skip_poll).optional_int("stalled", stalled_ago)
          out.int("cycles", @cycles).int("instructions", @instructions)
          save_position(out) unless boundary?
          out
        end

        def load_fields(input)
          @program_counter = input.word("pc", @program_counter)
          @stack_pointer = input.byte("sp", @stack_pointer)
          @a = input.byte("a", @a)
          @x = input.byte("x", @x)
          @y = input.byte("y", @y)
          @status.value = input.byte("p", @status.value)
          load_lines(input)
          @cycles = input.int("cycles", @cycles)
          @instructions = input.int("instructions", @instructions)
          stalled = input.optional_int("stalled")
          @stalled_at = stalled.nil? ? nil : @cycles - stalled
          load_position(input)
        end

        # What the fields leave to be worked out: whether the next step
        # writes.
        def restored!
          @pending_write = @writes[@index]
        end

        private

        # Cycles since the CPU last stalled, when that was this cycle or the
        # one before, the only ones an instruction looks back at.
        def stalled_ago
          stalled_at = @stalled_at
          return nil if stalled_at.nil?

          ago = @cycles - stalled_at
          ago.between?(0, 1) ? ago : nil
        end

        def load_lines(input)
          @nmi = input.bool("nmi", @nmi)
          @so_high = input.bool("so_high", @so_high)
          @irq_sample = input.bool("irq.sample", @irq_sample)
          @irq_pending = input.bool("irq.pending", @irq_pending)
          @boundary_irq = input.bool("irq.boundary", @boundary_irq)
          @nmi_sample = input.bool("nmi.sample", @nmi_sample)
          @nmi_pending = input.bool("nmi.pending", @nmi_pending)
          @boundary_nmi = input.bool("nmi.boundary", @boundary_nmi)
          @skip_poll = input.bool("skip_poll", @skip_poll)
        end

        def save_position(out)
          source = plan_source
          if source == JAMMED
            out.text("pos.seq", "jam")
            return
          end

          out.text("pos.seq", source == INTERRUPT ? "interrupt" : "op")
          out.int("pos.op", source) unless source == INTERRUPT
          out.int("pos.t", position_t(source)).bool("pos.crossed", @boundary_crossed)
          out.bool("pos.branch_taken", @branch_taken == true).bool("pos.brk", @brk)
          out.optional_int("pos.vector", @interrupt)
          out.optional_int("pos.address", @address).optional_int("pos.dummy_address", @dummy_address)
          out.optional_int("pos.value", @value).optional_int("pos.rmw", @rmw_result)
          out.optional_int("pos.pointer", @pointer)
        end

        # The cycles of the instruction or sequence run so far, counting the
        # opcode fetch as 1 and leaving out stalled cycles.
        def position_t(source)
          return @index if source == INTERRUPT

          MICROCODE.fetch(source).t_at(@index, @boundary_crossed)
        end

        def load_position(input)
          case input.choice("pos.seq", POSITIONS, "boundary")
          when "op" then load_instruction(input)
          when "interrupt" then load_interrupt(input)
          when "jam" then load_jam
          else load_boundary
          end
        end

        def load_instruction(input)
          micro = MICROCODE.fetch(input.byte("pos.op", 0xea))
          use_plan(micro.plan, micro.writes)
          @operation = micro.operation
          @optional_dummy = micro.optional_dummy
          @boundary_crossed = input.bool("pos.crossed", false)
          @index = micro.index_at(input.int("pos.t", 1), @boundary_crossed).clamp(1, micro.plan.length - 1)
          load_latches(input)
        end

        def load_interrupt(input)
          use_plan(INTERRUPT_PLAN, INTERRUPT_WRITES)
          @boundary_crossed = input.bool("pos.crossed", false)
          @index = input.int("pos.t", 1).clamp(1, INTERRUPT_PLAN.length - 1)
          load_latches(input)
        end

        def load_jam
          use_plan(JAMMED_PLAN, JAMMED_WRITES)
          @index = 0
          clear_latches
        end

        def load_boundary
          use_plan(FETCH_PLAN, FETCH_WRITES)
          @index = 0
          clear_latches
        end

        def load_latches(input)
          @branch_taken = input.bool("pos.branch_taken", false)
          @brk = input.bool("pos.brk", false)
          @interrupt = input.optional_int("pos.vector")
          @address = input.optional_int("pos.address")
          @dummy_address = input.optional_int("pos.dummy_address")
          @value = input.optional_int("pos.value")
          @rmw_result = input.optional_int("pos.rmw")
          @pointer = input.optional_int("pos.pointer")
        end

        # The working registers no step reads before the next instruction
        # sets them.
        def clear_latches
          @boundary_crossed = false
          @branch_taken = false
          @brk = false
          @interrupt = nil
          @address = nil
          @dummy_address = nil
          @value = nil
          @rmw_result = nil
          @pointer = nil
        end

        # Where the plan running comes from: an opcode's microcode, or FETCH,
        # INTERRUPT or JAMMED below it.
        def plan_source
          return FETCH if @plan.equal?(FETCH_PLAN)
          return INTERRUPT if @plan.equal?(INTERRUPT_PLAN)
          return JAMMED if @plan.equal?(JAMMED_PLAN)

          MICROCODE.index { |micro| micro.plan.equal?(@plan) && micro.operation == @operation } ||
            MICROCODE.index { |micro| micro.plan.equal?(@plan) }
        end

        def use_plan(plan, writes)
          @plan = plan
          @writes = writes
        end
      end
    end
  end
end
