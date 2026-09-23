# frozen_string_literal: true

module Badline
  module KernalTrap
    # PC trap on the KERNAL serial SAVE routine ($F5ED, the default ISAVE
    # vector target). Writes device 8 saves to a storage backend as a PRG
    # (load address followed by the memory range); other devices fall
    # through to the ROM. The ROM prints SAVING in direct mode and returns
    # into the trap, which then writes the file and leaves through the
    # ROM's own tail with the registers its UNLISTEN and return leave.
    class Save < File
      ADDRESS = 0xf5ed

      # ROM entry points: the SAVING message, the two line releases that
      # end UNLISTEN (clock, then data, leaving A as read from $DD00), the
      # successful return (CLC, RTS) and the MISSING FILE NAME error exit
      SAVING_MESSAGE = 0xf68f
      CLOCK_RELEASE = 0xee85
      DATA_RELEASE = 0xee97
      SAVE_DONE = 0xf657
      MISSING_FILE_NAME_EXIT = 0xf710

      SECONDARY = 0x61

      def initialize(cpu:, bus:, storage:)
        super
        @saving = false
      end

      def call
        return unless active?
        return finish if @saving

        @bus.poke(0xb9, SECONDARY)
        return @cpu.program_counter = MISSING_FILE_NAME_EXIT if name.empty?

        @bus.poke(0x90, 0x00)
        @saving = true
        continue_with(SAVING_MESSAGE, ADDRESS)
      end

      private

      def name
        Storage.parse_name(filename).first
      end

      def finish
        @saving = false
        @storage.write_file(name, payload)
        @bus.poke(0xac, @bus.peek(0xae))
        @bus.poke(0xad, @bus.peek(0xaf))
        @cpu.y = 0
        @cpu.status.overflow = true
        continue_with(CLOCK_RELEASE, DATA_RELEASE, SAVE_DONE)
      end

      # Start address at $C1/$C2 (STAL), end address (exclusive) at
      # $AE/$AF (EAL)
      def payload
        start = uint16(@bus.peek(0xc1), @bus.peek(0xc2))
        length = (uint16(@bus.peek(0xae), @bus.peek(0xaf)) - start) & 0xffff
        [low_byte(start), high_byte(start)] +
          Array.new(length) { |i| @bus.peek((start + i) & 0xffff) }
      end
    end
  end
end
