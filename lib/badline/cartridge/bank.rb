# frozen_string_literal: true

module Badline
  class Cartridge
    # One 8K bank of cartridge ROM. The chip decodes only the low address
    # lines, so the same bank answers at $8000, $A000 or $E000, and a smaller
    # chip mirrors across the window.
    class Bank
      def initialize(data)
        size = [1 << (data.length - 1).bit_length, 1].max
        @mask = size - 1
        @data = (data + ([0xff] * (size - data.length))).freeze
      end

      def peek(addr)
        @data[addr & @mask]
      end
      alias [] peek
    end

    EMPTY_BANK = Bank.new([0xff])
  end
end
