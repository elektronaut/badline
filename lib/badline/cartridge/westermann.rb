# frozen_string_literal: true

module Badline
  class Cartridge
    # 16K. Reading I/O 2 switches ROMH out (8K mode) until reset.
    class Westermann < Cartridge
      def readable_io_pages
        [0xdf]
      end

      def peek(addr)
        if addr >= 0xdf00
          self.mode = :rom8k
          changed!
        end
        open_bus(addr)
      end

      def reset
        self.mode = :rom16k
        changed!
      end

      private

      def install_chips(chips)
        roml, romh = banks_from(chips)
        @roml = bank(roml, 0)
        @romh = bank(romh, 0)
        reset
      end
    end
  end
end
