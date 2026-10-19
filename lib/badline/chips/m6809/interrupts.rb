# frozen_string_literal: true

module Badline
  module Chips
    class M6809
      # The IRQ, FIRQ, NMI and HALT lines, SYNC and CWAI.
      #
      # The CPU samples each line once a cycle, and an instruction boundary
      # sees the sample of two cycles before: a line asserted on the
      # instruction's next-to-last cycle is taken after it, as in Figures 8
      # and 9 of the MC6809E datasheet. NMI is an edge, latched until taken,
      # and ignored until a program loads S after reset.
      module Interrupts
        attr_reader :irq, :firq, :nmi, :halt

        # Asserts (true) or releases the IRQ line.
        def irq=(asserted)
          @irq = asserted
        end

        def firq=(asserted)
          @firq = asserted
        end

        def nmi=(asserted)
          @nmi_edge = true if asserted && !@nmi && @nmi_armed
          @nmi = asserted
        end

        # The HALT line: the CPU stops at the next instruction boundary and
        # leaves the bus alone until it is released.
        def halt=(asserted)
          @halt = asserted
        end

        def halted? = boundary? && @halt_seen

        # Whether the CPU is waiting in SYNC or CWAI, or running free.
        def waiting?
          step = @plan[@index]
          step == :sync_wait || step == :cwai_wait || step == :free_run || halted?
        end

        private

        def clear_interrupts
          @irq = @firq = @nmi = @halt = false
          @irq_latched = @irq_seen = false
          @firq_latched = @firq_seen = false
          @nmi_edge = @nmi_latched = @nmi_seen = false
          @halt_latched = @halt_seen = false
        end

        def sample_lines
          @irq_seen = @irq_latched
          @irq_latched = @irq
          @firq_seen = @firq_latched
          @firq_latched = @firq
          @nmi_seen = @nmi_latched
          @nmi_latched = @nmi_edge
          @halt_seen = @halt_latched
          @halt_latched = @halt
        end

        def interrupt_due?
          @nmi_seen || (@firq_seen && @cc.nobits?(FIRQ_MASK)) || (@irq_seen && @cc.nobits?(IRQ_MASK))
        end

        # The cycle that would have fetched an opcode reads it and drops it,
        # and the interrupt's sequence follows.
        def take_interrupt
          dead_pc
          @stack_u = false
          if @nmi_seen
            @operation = :enter_nmi
            switch_to(INTERRUPT_PLAN)
          elsif @firq_seen && @cc.nobits?(FIRQ_MASK)
            @operation = :enter_firq
            switch_to(FAST_INTERRUPT_PLAN)
          else
            @operation = :enter_irq
            switch_to(INTERRUPT_PLAN)
          end
        end

        def enter_nmi
          clear_nmi
          @cc |= ENTIRE
          interrupt_vector(0xfffc, IRQ_MASK | FIRQ_MASK)
        end

        def enter_firq
          @cc &= ~ENTIRE & 0xff
          interrupt_vector(0xfff6, IRQ_MASK | FIRQ_MASK)
        end

        def enter_irq
          @cc |= ENTIRE
          interrupt_vector(0xfff8, IRQ_MASK)
        end

        def interrupt_vector(vector, mask)
          @vector = vector
          @interrupt_mask = mask
        end

        def clear_nmi
          @nmi_edge = @nmi_latched = @nmi_seen = false
        end

        def reset_dead = @bus.read(0xfffe)

        def reset_hi
          @value = @bus.read(0xfffe) << 8
        end

        def reset_lo
          @pc = @value | @bus.read(0xffff)
        end

        def halted_cycle
          @index = 0
        end

        # SYNC leaves the bus alone until any interrupt line is asserted,
        # masked or not, then for one more cycle.
        def sync_wait
          if @nmi_latched || @firq_latched || @irq_latched
            switch_to(SYNC_END_PLAN)
          else
            @index -= 1
          end
        end

        # CWAI ANDs CC with its operand and sets E before it stacks.
        def cwai_mask
          @cc = (read_pc & @cc) | ENTIRE
        end

        # CWAI, all stacked, reads $FFFF until an interrupt it may take
        # comes, and then fetches that interrupt's vector.
        def cwai_wait
          dead_v
          if @nmi_latched
            clear_nmi
            interrupt_vector(0xfffc, IRQ_MASK | FIRQ_MASK)
          elsif @firq_latched && @cc.nobits?(FIRQ_MASK)
            interrupt_vector(0xfff6, IRQ_MASK | FIRQ_MASK)
          elsif @irq_latched && @cc.nobits?(IRQ_MASK)
            interrupt_vector(0xfff8, IRQ_MASK)
          else
            return @index -= 1
          end
          switch_to(WAITED_INTERRUPT_PLAN)
        end
      end
    end
  end
end
