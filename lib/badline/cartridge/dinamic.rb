# frozen_string_literal: true

module Badline
  class Cartridge
    # Dinamic: up to 16 8K banks. Reading $DE00-$DE0F selects the bank from
    # the low address bits.
    class Dinamic < Cartridge
      def readable_io_pages
        [0xde]
      end

      def peek(addr)
        if addr < 0xde10
          @roml = bank(@banks, addr & 0x0f)
          changed!
        end
        open_bus(addr)
      end

      def reset
        @roml = bank(@banks, 0)
        changed!
      end

      private

      def install_chips(chips)
        @banks = banks_from(chips).first
        self.mode = :rom8k
        reset
      end
    end
  end
end
