# frozen_string_literal: true

module Badline
  class REU
    # The REU's state for a snapshot: the REC's registers and the values
    # its counters start from, an armed or running transfer, the IRQ line,
    # the transfer's own state and the RAM. The size is the machine's
    # setup (Snapshot::Setup), so a restore finds an REU of the same size.
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

      # The sixteen bytes the REC's registers read from $DF00, without
      # what reading the status does, as VICE's REU1764 module holds them.
      def register_file = Array.new(16) { |register| register_value(register) }

      # Sets the registers from a register file, as writing them would but
      # without starting a transfer: each address and the length set both
      # the counter and the value it starts from. A command with the
      # execute bit set and the $FF00 trigger on arms the REC.
      def restore_registers(values)
        @status = (values[STATUS] & (INTERRUPT_PENDING | END_OF_BLOCK | FAULT)) | @chips
        @command = values[COMMAND]
        @c64 = @c64_start = values[C64_LOW] | (values[C64_HIGH] << 8)
        @expansion = @expansion_start = values[EXPANSION_LOW] | (values[EXPANSION_HIGH] << 8)
        @bank = @bank_start = values[EXPANSION_BANK] & @bank_bits
        @length = @length_start = values[LENGTH_LOW] | (values[LENGTH_HIGH] << 8)
        @interrupt_mask = values[INTERRUPT_MASK] | 0x1f
        @address_control = values[ADDRESS_CONTROL] | 0x3f
        @armed = @command.anybits?(EXECUTE) && @command.nobits?(NO_FF00_TRIGGER)
        @requested = @running = @ba_was_low = false
        interrupt(@status.anybits?(INTERRUPT_PENDING))
      end

      # The RAM, every byte of it, as one string.
      def ram_contents = @ram.contents

      def restore_ram(bytes) = @ram.restore(bytes)

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
