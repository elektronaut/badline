# frozen_string_literal: true

module Badline
  class Cartridge
    # 8K. Reading $DF00-$DFBF switches the ROM out, reading $DFC0-$DFFF
    # switches it back in.
    class RexUtility < Cartridge
      def readable_io_pages
        [0xdf]
      end

      def peek(addr)
        if addr >= 0xdf00
          self.mode = (addr & 0xff) < 0xc0 ? :off : :rom8k
          changed!
        end
        open_bus(addr)
      end

      def reset
        self.mode = :rom8k
        changed!
      end

      private

      def install_chips(chips)
        @roml = banks_from(chips).first.compact.first || EMPTY_BANK
        reset
      end
    end
  end
end
