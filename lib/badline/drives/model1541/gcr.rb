# frozen_string_literal: true

module Badline
  class Drive1541
    # Group code recording, the 1541's on-disk code. Each nibble becomes
    # five bits, chosen so that no code has more than two 0 bits in a row
    # and no run of codes has ten 1 bits in a row, which only a SYNC mark
    # has. Four bytes become five.
    module GCR
      CODES = [0x0a, 0x0b, 0x12, 0x13, 0x0e, 0x0f, 0x16, 0x17,
               0x09, 0x19, 0x1a, 0x1b, 0x0d, 0x1d, 0x1e, 0x15].freeze

      # Five-bit code => nibble, nil for the codes that aren't GCR.
      NIBBLES = Array.new(32) { |code| CODES.index(code) }.freeze

      module_function

      # Encodes a whole number of four-byte groups.
      def encode(bytes)
        out = []
        i = 0
        while i < bytes.length
          bits = 0
          4.times do |n|
            byte = bytes[i + n]
            bits = (bits << 10) | (CODES[byte >> 4] << 5) | CODES[byte & 0x0f]
          end
          4.downto(0) { |n| out << ((bits >> (n * 8)) & 0xff) }
          i += 4
        end
        out
      end

      # Decodes a whole number of five-byte groups, nil when any code
      # isn't GCR.
      def decode(bytes)
        out = []
        i = 0
        while i < bytes.length
          bits = 0
          5.times { |n| bits = (bits << 8) | bytes[i + n] }
          n = 7
          while n.positive?
            high = NIBBLES[(bits >> (n * 5)) & 0x1f]
            low = NIBBLES[(bits >> ((n - 1) * 5)) & 0x1f]
            return nil if high.nil? || low.nil?

            out << ((high << 4) | low)
            n -= 2
          end
          i += 5
        end
        out
      end
    end
  end
end
