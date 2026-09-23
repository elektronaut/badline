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

    # A cycle the VIC stalls through BA keeps sampling the lines, OR-ed with
    # the sample it already holds, but the boundary pipeline doesn't advance
    # and a skipped poll stays owed to the next real cycle.
    def sample_while_stalled
      @irq_sample ||= @irq && !interrupt_disabled_after_stall?
      @nmi_sample = true if @nmi
    end

    # A stalled CLI or SEI execute cycle masks with the I it is about to
    # set. Every other step masks with the current I, PLP included: its
    # pulled I only arrives with the stalled stack read.
    def interrupt_disabled_after_stall?
      return @status.interrupt? unless @plan.equal?(CPU::IMPLIED_PLAN)

      case @operation
      when :cli then false
      when :sei then true
      else @status.interrupt?
      end
    end

    # Runs in the opcode fetch cycle in place of the fetch, with no bus
    # access, and switches to the interrupt plan.
    def start_interrupt
      @interrupt = @boundary_nmi ? 0xfffa : 0xfffe
      @brk = false
      @plan = CPU::INTERRUPT_PLAN
      @writes = CPU::INTERRUPT_WRITES
      @index = 1
    end

    # BRK reads the byte after its opcode and ignores it, and selects the
    # IRQ vector.
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
      # An NMI that arrives before cycle 4 of a BRK or IRQ takes it over:
      # the sequence finishes with the NMI vector.
      @interrupt = 0xfffa if @interrupt == 0xfffe && @nmi_pending
      @nmi = false if @interrupt == 0xfffa
    end

    def op_int_vector_low
      @address = @memory.peek(@interrupt)
    end

    # Clears any interrupt that is pending, so the handler's first
    # instruction always runs before the next interrupt. This applies to
    # BRK too.
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
