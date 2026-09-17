# frozen_string_literal: true

module Badline
  class SID
    include Addressable

    def initialize
      addressable_at(0xd400, length: 2**10)
      @registers = Memory.new(length: 2**5)
    end

    def peek(addr)
      i = offset_of(addr) % (2**5)
      case i
      when 0x1d..0x1f then 0xff # Unused memory
      else @registers.peek(i)
      end
    end

    def poke(addr, value)
      i = offset_of(addr) % (2**5)
      @registers.poke(i, value)
    end
  end
end
