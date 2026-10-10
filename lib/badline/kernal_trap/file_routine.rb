# frozen_string_literal: true

module Badline
  module KernalTrap
    class FileRoutine < Routine
      private

      def active?
        kernal_mapped? && @bus.peek(0xba) == DEVICE
      end

      def filename
        Storage.strip_drive_prefix(full_filename)
      end

      # Filename pointer at $BB/$BC, length at $B7
      def full_filename
        pointer = uint16(@bus.peek(0xbb), @bus.peek(0xbc))
        bytes = Array.new(@bus.peek(0xb7)) do |i|
          @layout.filename_byte(@bus, (pointer + i) & 0xffff)
        end
        Storage.ascii(bytes)
      end
    end
  end
end
