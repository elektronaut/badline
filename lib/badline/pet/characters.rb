# frozen_string_literal: true

module Badline
  class PET
    # The character ROM as the video reads it: 2K of two sets, graphics
    # (upper case and graphics) from $000 and text (lower and upper case)
    # from $400, 128 characters of 8 rows each. Bit 7 of a screen code
    # inverts the character's rows, as the hardware does, so #rows holds
    # 256 codes a set, each row at (set << 11) | (code << 3) | row.
    class Characters
      TEXT = 0x800

      attr_reader :rows

      def initialize(file)
        rom = ROM.read(file)
        @rows = Array.new(0x1000) do |index|
          set = index >> 11
          code = (index >> 3) & 0xff
          bits = rom[(set << 10) | ((code & 0x7f) << 3) | (index & 0x07)]
          code >= 0x80 ? bits ^ 0xff : bits
        end
      end
    end
  end
end
