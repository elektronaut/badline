# frozen_string_literal: true

module Badline
  class Memory
    include Addressable

    def initialize(initial = [], length: 2**16, start: 0)
      addressable_at(start, length:)
      @storage = zero_fill(initial)
    end

    def peek(addr)
      @storage[offset_of(addr)]
    end

    def poke(addr, value)
      @storage[offset_of(addr)] = value
      value
    end

    def read(addr, length)
      (addr...(addr + length)).to_a.map { |a| peek(a) }
    end

    def write(addr, bytes)
      Array(bytes).each_with_index { |b, i| poke(addr + i, b) }
    end

    private

    def blank_value
      0
    end

    def zero_fill(initial)
      array = initial.dup
      array.fill(blank_value, array.length, length - array.length) if array.length < length
      array
    end
  end
end
