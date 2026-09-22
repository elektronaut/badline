# frozen_string_literal: true

module Badline
  module Interrupts
    private

    def handle_interrupt(vector, brk: false)
      # BRK already burned this cycle on the operand fetch its addressing
      # mode discards.
      internal_cycle unless brk

      pc = program_counter
      pc = (pc + 1) & 0xffff if brk

      write_byte(stack_address, high_byte(pc))
      @stack_pointer = (@stack_pointer - 1) & 0xff
      write_byte(stack_address, low_byte(pc))
      @stack_pointer = (@stack_pointer - 1) & 0xff
      write_byte(stack_address,
                 status.clone.tap { |s| s.break = brk }.value)
      @stack_pointer = (@stack_pointer - 1) & 0xff
      status.interrupt = true
      # An NMI asserted before cycle 4 hijacks a BRK/IRQ sequence in progress.
      vector = 0xfffa if vector == 0xfffe && @nmi_pending
      @nmi = false if vector == 0xfffa
      @program_counter = read_word(vector)
      # Interrupt sequences (BRK included) do not poll at their end, so the
      # handler's first instruction always runs before another interrupt.
      @irq_sample = @irq_pending = false
      @nmi_sample = @nmi_pending = false
    end

    def service_interrupt(nmi_pending)
      @cycles += 1
      @interrupt = nmi_pending ? 0xfffa : 0xfffe
      handle_interrupt(@interrupt)
      @interrupt = nil
    end

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
  end
end
