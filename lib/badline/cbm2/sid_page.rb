# frozen_string_literal: true

module Badline
  class CBM2
    # Page $DA of segment 15: the SID's 32 registers, repeated over the
    # page.
    class SIDPage
      def initialize(sid)
        @sid = sid
      end

      def peek(addr) = @sid.peek(0xda00 | (addr & 0x1f))

      def poke(addr, value)
        @sid.poke(0xda00 | (addr & 0x1f), value)
      end
    end
  end
end
