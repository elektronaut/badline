# frozen_string_literal: true

module Badline
  module KernalTrap
    class FileRoutine < Routine
      private

      def active?
        kernal_mapped? && @bus.peek(zero_page.device) == DEVICE
      end

      def filename
        Storage.strip_drive_prefix(full_filename)
      end

      # The file name FNADR points to, FNLEN bytes long.
      def full_filename
        pointer = peek_word(zero_page.filename_address)
        bytes = Array.new(@bus.peek(zero_page.filename_length)) do |i|
          @layout.filename_byte(@bus, (pointer + i) & 0xffff)
        end
        Storage.ascii(bytes)
      end
    end
  end
end
