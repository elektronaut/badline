# frozen_string_literal: true

module Badline
  module RAMExpansion
    # The +60K: a second bank of RAM behind $1000-$FFFF, selected by bit 7
    # of $D100. $0000-$0FFF stays the machine's own RAM, and so does all of
    # what the VIC sees.
    class Plus60k
      include Banking

      def initialize(ram)
        @low_ram = @video_ram = @high_ram = ram
        @banks = [ram, Memory.new]
        @on_change = nil
      end

      def poke(_addr, value)
        @high_ram = @banks[value >> 7]
        @on_change&.call
      end

      def reset!
        @high_ram = @banks[0]
      end

      def power_on!
        @banks[1].clear!
      end
    end
  end
end
