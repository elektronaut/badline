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

    # Every byte, as a copy.
    def snapshot = @storage.dup

    def write(addr, bytes)
      Array(bytes).each_with_index { |b, i| poke(addr + i, b) }
    end

    # Every byte as one record of a keyed snapshot module, under `key`.
    def save_fields(out, key) = out.bytes(key, @storage)

    def load_fields(input, key) = input.bytes_into(key, @storage)

    # Refills the whole memory as if newly built with `initial`
    def clear!(initial = [])
      @storage.replace(zero_fill(initial))
    end

    private

    def blank_value
      0
    end

    def zero_fill(initial)
      array = Array.new(length, blank_value)
      initial.each_with_index { |v, i| array[i] = v.to_i unless v.nil? }
      array
    end
  end
end
