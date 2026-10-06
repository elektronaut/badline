# frozen_string_literal: true

module Badline
  module KernalTrap
    # PC trap on the KERNAL serial SAVE routine (the default ISAVE vector
    # target, $F5ED on the C64). Hands device 8 saves to the virtual drive as a PRG
    # (load address followed by the memory range); other devices fall
    # through to the ROM, and so do saves to a disk that doesn't take them
    # whole. The ROM prints SAVING in direct mode and returns
    # into the trap, which then writes the file and leaves through the
    # ROM's own tail with the registers its UNLISTEN and return leave. A
    # write that fails, to a full disk, a name already on it or a host file
    # that can't be written, ends the way a 1541 ends a SAVE it can't
    # write: the drive stops listening, so ST reads DEVICE NOT PRESENT,
    # and the ROM returns without an error. A "@" before the drive prefix
    # writes over a file of the same name.
    class Save < File
      SECONDARY = 0x61

      # ST bit at $90
      DEVICE_NOT_PRESENT = 0x80

      def initialize(cpu:, bus:, layout:, drive:)
        super(cpu:, bus:, layout:)
        @drive = drive
        @saving = false
      end

      def save_state(out)
        out.boolean(@saving)
      end

      def load_state(input)
        @saving = input.boolean?
      end

      def call
        return unless active?
        return finish if @saving
        return unless @drive.saves?

        @bus.poke(0xb9, SECONDARY)
        return @cpu.program_counter = @layout.missing_file_name_exit if name.empty?

        @bus.poke(0x90, 0x00)
        @saving = true
        continue_with(@layout.saving_message, @layout.save)
      end

      private

      def name
        Storage.parse_name(filename).first
      end

      def finish
        @saving = false
        saved = @drive.save(name, payload, replace: full_filename.start_with?("@"))
        @bus.poke(0x90, DEVICE_NOT_PRESENT) unless saved
        @bus.poke(0xac, @bus.peek(0xae))
        @bus.poke(0xad, @bus.peek(0xaf))
        @cpu.y = 0
        @cpu.status.overflow = true
        continue_with(@layout.clock_release, @layout.data_release, @layout.save_done)
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
