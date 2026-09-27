# frozen_string_literal: true

module Badline
  class Drive1541
    # The drive CPU's bus. The decoder looks at A15, A12, A11 and A10 only:
    #
    # $0000-$17FF - 2 KB of RAM, mirrored
    # $1800-$1BFF - VIA 1, its sixteen registers mirrored
    # $1C00-$1FFF - VIA 2, its sixteen registers mirrored
    # $2000-$7FFF - $0000-$1FFF again, since A13 and A14 aren't decoded
    # $8000-$BFFF - the ROM again, since A14 isn't decoded
    # $C000-$FFFF - the DOS ROM
    #
    # Writes to the ROM go nowhere.
    class Bus
      include Addressable

      RAM_SIZE = 0x0800

      attr_reader :ram, :rom, :via1, :via2

      def initialize(rom:, via1:, via2:)
        addressable_at(0, length: 2**16)
        @ram = Memory.new([], length: RAM_SIZE, start: 0)
        @rom = rom
        @via1 = via1
        @via2 = via2
      end

      def peek(addr)
        return @rom.peek(addr | 0x4000) if addr >= 0x8000

        addr &= 0x1fff
        if addr < 0x1800
          @ram.peek(addr & 0x07ff)
        elsif addr < 0x1c00
          @via1.peek(addr)
        else
          @via2.peek(addr)
        end
      end

      def poke(addr, value)
        return if addr >= 0x8000

        addr &= 0x1fff
        if addr < 0x1800
          @ram.poke(addr & 0x07ff, value)
        elsif addr < 0x1c00
          @via1.poke(addr, value)
        else
          @via2.poke(addr, value)
        end
      end
    end
  end
end
