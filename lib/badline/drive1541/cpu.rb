# frozen_string_literal: true

module Badline
  class Drive1541
    # The drive's 6502, on the drive's Bus.
    class CPU
      include Badline::CPU::Core

      # Everything the CPU holds but its cycle and instruction counts: the
      # registers, the interrupt lines and pipeline, and what the last
      # instruction left in its working registers. Drive::Idle compares
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
    end
  end
end
