# frozen_string_literal: true

module Badline
  class AddressBus
    # Stands in for an I/O page that a second or third SID shares: each 32
    # bytes of it go to the SID placed there, or on to what the page maps
    # otherwise.
    class SIDSlots
      def initialize(target)
        @slots = Array.new(8, target)
      end

      # Puts the SID in front of its 32 bytes and returns the page.
      def place(sid)
        @slots[(sid.start >> 5) & 7] = sid
        self
      end

      def peek(addr) = @slots[(addr >> 5) & 7].peek(addr)

      def poke(addr, value)
        @slots[(addr >> 5) & 7].poke(addr, value)
      end
    end
  end
end
