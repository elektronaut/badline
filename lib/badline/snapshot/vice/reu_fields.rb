# frozen_string_literal: true

module Badline
  class REU
    # The REU as VICE's REU1764 module holds it (Snapshot::Vice::REU1764):
    # the registers as they read from $DF00, and the RAM.
    module ViceFields
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
    end

    include ViceFields
  end
end
