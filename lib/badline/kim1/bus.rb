# frozen_string_literal: true

module Badline
  class KIM1
    # The CPU's bus. The board decodes A10-A12 into eight 1K blocks and
    # leaves A13-A15 alone, so the 8K repeats through all 64K, and the
    # vectors at $FFFA-$FFFF are the monitor's at $1FFA-$1FFF (User Manual,
    # figure 3.12 and section 6.2):
    #
    # $0000-$03FF - the 1K of RAM
    # $0400-$16FF - nothing
    # $1700-$173F - U3's ports and timer, its 16 registers repeated
    # $1740-$177F - U2's
    # $1780-$17BF - U3's 64 bytes of RAM
    # $17C0-$17FF - U2's
    # $1800-$1BFF - U3's ROM, the tape routines
    # $1C00-$1FFF - U2's ROM, the monitor
    #
    # A read from nothing finds the last byte on the bus. Writes to ROM
    # and to nothing go nowhere.
    class Bus
      include Addressable

      attr_reader :ram

      # The last byte the CPU read or wrote.
      attr_reader :data

      # +monitor+ is U2, the 6530-002, and +user+ U3, the 6530-003.
      def initialize(monitor, user)
        addressable_at(0, length: 2**16)
        @u2 = monitor
        @u3 = user
        @ram = Memory.new([], length: 0x400, start: 0)
        @data = 0
      end

      def peek(addr)
        offset = addr & 0x1fff
        block = offset >> 10
        @data = if block.zero?
                  @ram.peek(offset)
                elsif block == 7
                  @u2.read_rom(offset)
                elsif block == 6
                  @u3.read_rom(offset)
                elsif (offset >> 8) == 0x17
                  read_chips(offset)
                else
                  @data
                end
      end

      def poke(addr, value)
        @data = value
        offset = addr & 0x1fff
        if offset < 0x400
          @ram.poke(offset, value)
        elsif (offset >> 8) == 0x17
          write_chips(offset, value)
        end
      end

      def power_on!
        @ram.clear!
        @u2.ram.map! { 0 }
        @u3.ram.map! { 0 }
      end

      private

      # A6 picks U2 over U3, and A7 the RAM over the registers.
      def read_chips(offset)
        ram = offset.anybits?(0x80)
        if offset.anybits?(0x40)
          ram ? @u2.read_ram(offset) : @u2.peek(offset & 0x0f)
        else
          ram ? @u3.read_ram(offset) : @u3.peek(offset & 0x0f)
        end
      end

      def write_chips(offset, value)
        ram = offset.anybits?(0x80)
        if offset.anybits?(0x40)
          ram ? @u2.write_ram(offset, value) : @u2.poke(offset & 0x0f, value)
        else
          ram ? @u3.write_ram(offset, value) : @u3.poke(offset & 0x0f, value)
        end
      end
    end
  end
end
