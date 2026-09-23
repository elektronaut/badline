# frozen_string_literal: true

module Badline
  module KernalTrap
    # PC trap on the KERNAL serial SAVE routine ($F5ED, the default ISAVE
    # vector target). Writes device 8 saves to a storage backend as a PRG
    # (load address followed by the memory range); other devices fall
    # through to the ROM.
    class Save < File
      ADDRESS = 0xf5ed

      def call
        return unless active?

        name = Storage.parse_name(filename).first
        if name.empty?
          error(MISSING_FILENAME)
        else
          @storage.write_file(name, payload)
          finish
        end
        return_to_caller
      end

      private

      # Start address at $C1/$C2 (STAL), end address (exclusive) at
      # $AE/$AF (EAL)
      def payload
        start = uint16(@bus.peek(0xc1), @bus.peek(0xc2))
        length = (uint16(@bus.peek(0xae), @bus.peek(0xaf)) - start) & 0xffff
        [low_byte(start), high_byte(start)] +
          Array.new(length) { |i| @bus.peek((start + i) & 0xffff) }
      end

      def finish
        @bus.poke(0x90, 0x00)
        @cpu.status.carry = false
      end
    end
  end
end
