# frozen_string_literal: true

module Badline
  module KernalTrap
    # PC trap on the KERNAL serial SAVE routine (the default ISAVE vector
    # target, $F5ED on the C64, $F685 on the VIC-20). Hands device 8 saves
    # to the virtual drive as a PRG (load address followed by the memory
    # range); other devices fall through to the ROM, and so do saves to a
    # disk that doesn't take them whole. The ROM prints SAVING in direct
    # mode and returns into the trap, which then writes the file and leaves
    # through the ROM's own tail with the registers its UNLISTEN and return
    # leave. A
    # write that fails, to a full disk, a name already on it or a host file
    # that can't be written, ends the way a 1541 ends a SAVE it can't
    # write: the drive stops listening, so ST reads DEVICE NOT PRESENT,
    # and the ROM returns without an error. A "@" before the drive prefix
    # writes over a file of the same name.
    class Save < FileRoutine
      SECONDARY = 0x61

      # ST bit
      DEVICE_NOT_PRESENT = 0x80

      def initialize(cpu:, bus:, layout:, dos:)
        super(cpu:, bus:, layout:)
        @dos = dos
        @saving = false
      end

      def call
        return unless active?
        return finish if @saving
        return unless @dos.saves?

        @bus.poke(zero_page.secondary_address, SECONDARY)
        return @cpu.program_counter = @layout.missing_file_name_exit if name.empty?

        @bus.poke(zero_page.status, 0x00)
        @saving = true
        continue_with(@layout.saving_message, @layout.save)
      end

      private

      def name
        Storage.parse_name(filename).first
      end

      def finish
        @saving = false
        saved = @dos.save(name, payload, replace: full_filename.start_with?("@"))
        @bus.poke(zero_page.status, DEVICE_NOT_PRESENT) unless saved
        poke_word(zero_page.start_address, peek_word(zero_page.end_address))
        @cpu.y = 0
        @cpu.status.overflow = true
        continue_with(@layout.clock_release, @layout.data_release, @layout.save_done)
      end

      # Start address at STAL, end address (exclusive) at EAL
      def payload
        start = peek_word(zero_page.save_start)
        length = (peek_word(zero_page.end_address) - start) & 0xffff
        [low_byte(start), high_byte(start)] +
          Array.new(length) { |i| @layout.file_byte(@bus, (start + i) & 0xffff) }
      end
    end
  end
end
