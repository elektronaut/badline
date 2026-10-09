# frozen_string_literal: true

module Badline
  class Drive1541
    # The drive CPU's bus. The decoder looks at A15, A12, A11 and A10 only:
    #
    # $0000-$07FF - 2 KB of RAM
    # $0800-$17FF - nothing: open bus
    # $1800-$1BFF - VIA 1, its sixteen registers mirrored
    # $1C00-$1FFF - VIA 2, its sixteen registers mirrored
    # $2000-$7FFF - $0000-$1FFF again, since A13 and A14 aren't decoded
    # $8000-$BFFF - the ROM again, since A14 isn't decoded
    # $C000-$FFFF - the DOS ROM
    #
    # Writes to the ROM and to open bus go nowhere. A read from open bus
    # finds the last byte on the data bus, which for LDA abs or LDA (zp),Y
    # is the address's high byte, and for an indexed read that crosses a
    # page is what its dummy read found. VICE-testprogs drive/openbus pins
    # both on a real 1541.
    #
    # While Idle records a pass of the DOS's idle loop, the bus watches it,
    # and while Idle looks for an orbit, it guards the drive (see
    # Drive::Watch).
    class Bus
      include Addressable
      include Drive::Watch

      attr_reader :ram, :rom, :via1, :via2, :data

      def initialize(rom:, via1:, via2:)
        addressable_at(0, length: 2**16)
        @ram = Memory.new([], length: 0x0800, start: 0)
        @rom = rom
        @via1 = via1
        @via2 = via2
        @data = 0
        init_watch
      end

      # The last byte on the data bus and the RAM. What a watched stretch
      # touched is Idle's, and a restored bus isn't watching.
      def save_state(out)
        out.int(@data)
        @ram.save_state(out)
      end

      def load_state(input)
        @data = input.int
        @ram.load_state(input)
        @watching = false
      end

      def peek(addr)
        return @data = @rom.peek(addr | 0x4000) if addr >= 0x8000

        addr &= 0x1fff
        watch_read(addr) if @watching
        @data = if addr < 0x0800
                  @ram.peek(addr)
                elsif addr < 0x1800
                  @data
                elsif addr < 0x1c00
                  @via1.peek(addr)
                else
                  @via2.peek(addr)
                end
      end

      def poke(addr, value)
        @data = value
        return if addr >= 0x8000

        addr &= 0x1fff
        if addr < 0x0800
          touch(addr) if @recording
          @ram.poke(addr, value)
        elsif addr >= 0x1c00
          @via2.poke(addr, value)
        elsif addr >= 0x1800
          @via1.poke(addr, value)
        end
        watch_write(addr) if @watching
      end
    end
  end
end
