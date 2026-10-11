# frozen_string_literal: true

module Badline
  # Colour RAM is four bits wide. A CPU read takes the upper nibble off the
  # open data bus, which still holds the byte the VIC fetched in phi1.
  class ColorMemory < Memory
    def initialize(vic, start: 0xd800, length: 2**10)
      super(start:, length:)
      @vic = vic
    end

    def peek(addr)
      (@vic.phi1_data & 0xf0) | @storage[offset_of(addr)]
    end

    def poke(addr, value)
      super(addr, value & 0x0f)
    end

    # The four bits the cell stores, as the VIC's c-access sees them.
    def nibble(addr)
      @storage[offset_of(addr)]
    end
  end
end
