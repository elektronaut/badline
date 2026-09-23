# frozen_string_literal: true

module Badline
  class Cartridge
    # 16K. Reading I/O 1 switches ROMH out (8K mode), writing it switches
    # ROMH back in.
    class SimonsBasic < Cartridge
      def readable_io_pages
        [0xde]
      end

      def peek(addr)
        select_mode(:rom8k) if addr < 0xdf00
        open_bus(addr)
      end

      def poke(addr, _value)
        select_mode(:rom16k) if addr < 0xdf00
      end

      def reset
        select_mode(:rom16k)
      end

      private

      def select_mode(mode)
        self.mode = mode
        changed!
      end

      def install_chips(chips)
        roml, romh = banks_from(chips)
        @roml = roml.first
        @romh = romh.first
        reset
      end
    end
  end
end
