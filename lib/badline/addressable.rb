# frozen_string_literal: true

module Badline
  module Addressable
    include IntegerHelper

    class ReadOnlyMemoryError < StandardError; end
    class OutOfBoundsError < StandardError; end

    attr_reader :start, :length, :end

    def addressable_at(start = 0, length: 2**16)
      @start = start
      @length = length
      @end = start + length
    end

    def range
      start..(start + (length - 1))
    end

    def in_range?(addr)
      addr >= @start && addr < @end
    end

    def peek(_addr)
      raise NoMethodError
    end

    def peek16(addr)
      uint16(peek(addr), peek(addr + 1))
    end

    def poke(_addr, _value)
      raise NoMethodError
    end

    def poke16(addr, value)
      poke(addr, low_byte(value))
      poke(addr + 1, high_byte(value))
      value
    end

    def [](addr)
      peek(addr)
    end

    def []=(addr, value)
      poke(addr, value)
    end

    private

    # Offset of an address within this region. Not named `index`: Spinel
    # resolves calls by name across the whole program, and a common name
    # pulls unrelated receivers into this one's inferred parameter type.
    def offset_of(addr)
      i = addr - @start
      raise OutOfBoundsError, "#{addr.inspect} (#{@start}..#{@end - 1})" unless i >= 0 && i < @length

      i
    end
  end
end
