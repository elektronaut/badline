# frozen_string_literal: true

module Badline
  module Interrupts
    BREAK_MASK = 0x10

    private

    # Samples the IRQ line and the NMI latch once per cycle. An instruction
    # boundary commits the sample taken on its second-to-last cycle.
    def poll
      if @skip_poll
        @skip_poll = false
        return
      end
      @irq_pending = @irq_sample
      @nmi_pending = @nmi_sample
      @irq_sample = @irq && !@status.interrupt?
      @nmi_sample = @nmi
    end

    # An interrupt spends its first cycle deciding to take the vector, with
    # nothing on the bus, and then runs the same sequence as BRK.
    def start_interrupt
      @interrupt = @boundary_nmi ? 0xfffa : 0xfffe
      @brk = false
      @plan = CPU::INTERRUPT_PLAN
      @writes = CPU::INTERRUPT_WRITES
      @index = 1
    end

    # BRK burns the operand fetch its addressing mode discards, and arms
    # the IRQ vector as it goes.
    def op_brk_dummy
      @memory.peek(@program_counter)
      @interrupt = 0xfffe
      @brk = true
    end

    def op_int_push_pch
      @address = @brk ? (@program_counter + 1) & 0xffff : @program_counter
      @memory.poke(stack_address, high_byte(@address))
      @stack_pointer = (@stack_pointer - 1) & 0xff
    end

    def op_int_push_pcl
      @memory.poke(stack_address, low_byte(@address))
      @stack_pointer = (@stack_pointer - 1) & 0xff
    end

    def op_int_push_status
      value = @brk ? @status.value | BREAK_MASK : @status.value & ~BREAK_MASK
      @memory.poke(stack_address, value)
      @stack_pointer = (@stack_pointer - 1) & 0xff
      @status.interrupt = true
      # An NMI asserted before cycle 4 hijacks a BRK/IRQ sequence in progress.
      @interrupt = 0xfffa if @interrupt == 0xfffe && @nmi_pending
      @nmi = false if @interrupt == 0xfffa
    end

    def op_int_vector_low
      @address = @memory.peek(@interrupt)
    end

    # Interrupt sequences (BRK included) do not poll at their end, so the
    # handler's first instruction always runs before another interrupt.
    def op_int_vector_high
      high = @memory.peek((@interrupt + 1) & 0xffff)
      @program_counter = @address | (high << 8)
      @irq_sample = @irq_pending = false
      @nmi_sample = @nmi_pending = false
      @interrupt = nil
      if @brk
        @status.break = false
        end_instruction
      else
        end_sequence
      end
    end
  end
end
