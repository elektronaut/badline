# frozen_string_literal: true

module Badline
  class PET
    # The character ROM as the video reads it: 2K of two sets, graphics
    # (upper case and graphics) from $000 and text (lower and upper case)
    # from $400, 128 characters of 8 rows each. Bit 7 of a screen code
    # inverts the character's rows, as the hardware does, so #rows holds
    # 256 codes a set, each row at (set << 11) | (code << 3) | row. A 4K
    # ROM, the 8296's, holds two such halves, the second at HALF.
    class Characters
      TEXT = 0x800

      HALF = 0x1000

      attr_reader :rows

      def initialize(file)
        rom = ROM.read(file)
        @rows = Array.new(rom.length << 1) do |index|
          set = index >> 11
          code = (index >> 3) & 0xff
          bits = rom[(set << 10) | ((code & 0x7f) << 3) | (index & 0x07)]
          code >= 0x80 ? bits ^ 0xff : bits
        end
      end

      # Whether the ROM holds two halves.
      def halves? = @rows.length > HALF
    end
  end
end
