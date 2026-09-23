# frozen_string_literal: true

module Badline
  module KernalTrap
    class Drive
      # The numbers a DOS command takes. The DOS skips spaces, commas and
      # cursor-rights before a parameter, reads it from the characters $30
      # to $3F that follow, the low nibble of each, and skips whatever
      # character ends it. So "18,\x02" reads as 18 and 0, ":" to "?" are
      # digits 10 to 15, and a run of digits keeps its last three.
      module Parameters
        # Space, comma and cursor-right
        GAPS = [0x20, 0x2c, 0x1d].freeze

        def self.parse(text)
          rest = text.to_s.bytes
          values = []
          until (rest = rest.drop_while { |byte| GAPS.include?(byte) }).empty?
            digits = rest.take_while { |byte| byte.between?(0x30, 0x3f) }
            values << digits.last(3).reduce(0) { |value, digit| (value * 10) + (digit & 0x0f) }
            rest = rest.drop(digits.length + 1)
          end
          values
        end
      end
    end
  end
end
