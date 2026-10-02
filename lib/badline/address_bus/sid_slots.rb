# frozen_string_literal: true

module Badline
  class AddressBus
    # Stands in for a page of I/O that a second or third SID shares: each 32
    # bytes of it go to the SID placed there, or else to the first SID's
    # mirrors in `$d400-$d7ff`, and to the open bus in I/O 1 and 2.
    class SIDSlots
      attr_reader :page

      def initialize(page, first, open_bus)
        @page = page
        @io = page >= 0xde
        @first = first
        @open_bus = open_bus
        @sids = []
        @slots = Array.new(8, -1)
      end

      def place(sid)
        @slots[(sid.start >> 5) & 7] = @sids.size
        @sids << sid
      end

      def peek(addr)
        index = @slots[(addr >> 5) & 7]
        return @sids[index].peek(addr) unless index.negative?

        @io ? @open_bus.peek(addr) : @first.peek(addr)
      end

      def poke(addr, value)
        index = @slots[(addr >> 5) & 7]
        if !index.negative?
          @sids[index].poke(addr, value)
        elsif !@io
          @first.poke(addr, value)
        end
      end
    end
  end
end
