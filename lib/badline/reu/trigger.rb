# frozen_string_literal: true

module Badline
  class REU
    # Stands in for the page at $FF00 in the write table, passing each
    # write on to what is mapped there and telling the REC when $FF00 is
    # written, which starts an armed transfer.
    class Trigger
      ADDRESS = 0xff00

      def initialize(reu)
        @reu = reu
        @target = nil
      end

      # Puts the trigger in front of target and returns it.
      def wrap(target)
        @target = target
        self
      end

      def peek(addr)
        @target.peek(addr)
      end

      def poke(addr, value)
        @target.poke(addr, value)
        @reu.ff00_written if addr == ADDRESS
      end
    end
  end
end
