# frozen_string_literal: true

module Badline
  class Cartridge
    # 8K. Writing I/O 1 switches the ROM in, writing I/O 2 switches it out.
    # Both I/O pages read the last 512 bytes of the ROM.
    class Mach5 < Cartridge
      def readable_io_pages
        [0xde, 0xdf]
      end

      def peek(addr)
        @roml.peek(addr)
      end

      def poke(addr, _value)
        self.mode = addr < 0xdf00 ? :rom8k : :off
        changed!
      end

      def reset
        self.mode = :rom8k
        changed!
      end

      private

      def install_chips(chips)
        @roml = banks_from(chips).first.compact.first
        reset
      end
    end
  end
end
