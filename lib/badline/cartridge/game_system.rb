# frozen_string_literal: true

module Badline
  class Cartridge
    # C64 Game System / System 3: up to 64 8K banks. Any access to
    # $DE00-$DEFF selects the bank from the low six address bits; the data
    # is ignored.
    class GameSystem < Cartridge
      def readable_io_pages
        [0xde]
      end

      def peek(addr)
        select(addr) if addr < 0xdf00
        open_bus(addr)
      end

      def poke(addr, _value)
        select(addr) if addr < 0xdf00
      end

      def reset
        select(0)
      end

      private

      def select(addr)
        @roml = bank(@banks, addr & 0x3f)
        changed!
      end

      def install_chips(chips)
        @banks = banks_from(chips).first
        self.mode = :rom8k
        reset
      end
    end
  end
end
