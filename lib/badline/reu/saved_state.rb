# frozen_string_literal: true

module Badline
  class REU
    # The REU's state for a snapshot: the REC's registers and the values
    # its counters start from, an armed or running transfer, the IRQ line,
    # the transfer's own state and the RAM. The size is the machine's
    # setup (Snapshot::C64Setup), so a restore finds an REU of the same size.
    module SavedState
      def size_kb = @size_kb

      def save_state(out)
        out.marker("REU")
        [@status, @command, @c64, @c64_start, @expansion, @expansion_start, @bank, @bank_start, @length,
         @length_start, @interrupt_mask, @address_control].each { |value| out.int(value) }
        out.boolean(@armed).boolean(@requested).boolean(@running).boolean(@irq).boolean(@ba_was_low)
        @dma.save_state(out)
        @ram.save_state(out)
      end

      # The IRQ line comes back as it was without calling back into the
      # machine, which reads it again afterwards.
      def load_state(input)
        input.marker("REU")
        load_registers(input)
        @armed = input.boolean?
        @requested = input.boolean?
        @running = input.boolean?
        @irq = input.boolean?
        @ba_was_low = input.boolean?
        @dma.load_state(input)
        @ram.load_state(input)
      end

      private

      def load_registers(input)
        @status = input.int
        @command = input.int
        @c64 = input.int
        @c64_start = input.int
        @expansion = input.int
        @expansion_start = input.int
        @bank = input.int
        @bank_start = input.int
        @length = input.int
        @length_start = input.int
        @interrupt_mask = input.int
        @address_control = input.int
      end
    end
  end
end
