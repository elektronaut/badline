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
    #
    # The board takes more RAM, as RAM_CONFIGURATIONS names it: the stock
    # 1K, 5K with a board in K1-K4 filling $0400-$13FF, or those 5K and
    # RAM at $2000-$DFFF, with an expansion that decodes A13-A15 and
    # repeats the first 8K only at $E000-$FFFF, so the vectors are still
    # the monitor's (User Manual, sections 6.1 and 6.2).
    class Bus
      include Addressable

      # Each configuration's end of RAM in the first 8K, and where the
      # first 8K stops repeating, past what RAM fills above it.
      RAM_CONFIGURATIONS = { "1k": [0x0400, 0x2000], "5k": [0x1400, 0x2000], expanded: [0x1400, 0xe000] }.freeze

      # The RAM, and the key of RAM_CONFIGURATIONS it comes as.
      attr_reader :ram, :ram_configuration

      # The last byte the CPU read or wrote.
      attr_reader :data

      # +monitor+ is U2, the 6530-002, and +user+ U3, the 6530-003, with
      # the RAM `ram` names.
      def initialize(monitor, user, ram: :"1k")
        addressable_at(0, length: 2**16)
        raise ArgumentError, "no KIM-1 RAM configuration named #{ram}" unless RAM_CONFIGURATIONS.key?(ram)

        @u2 = monitor
        @u3 = user
        @ram_configuration = ram
        ends = RAM_CONFIGURATIONS.fetch(ram)
        @low_end = ends[0]
        @mirror_end = ends[1]
        @ram = Memory.new([], length: @mirror_end == 0x2000 ? @low_end : @mirror_end, start: 0)
        @data = 0
      end

      # The RAM in K, without the 6530s' 64 bytes each.
      def ram_kb = (@low_end + @mirror_end - 0x2000) >> 10

      # Whether RAM answers at `addr`, the board's or a 6530's.
      def ram?(addr)
        offset = addr < 0x2000 || addr >= @mirror_end ? addr & 0x1fff : addr
        offset < @low_end || offset >= 0x2000 || offset.between?(0x1780, 0x17ff)
      end

      def peek(addr)
        offset = addr < 0x2000 || addr >= @mirror_end ? addr & 0x1fff : addr
        @data = if offset < @low_end || offset >= 0x2000
                  @ram.peek(offset)
                elsif offset >= 0x1c00
                  @u2.read_rom(offset)
                elsif offset >= 0x1800
                  @u3.read_rom(offset)
                elsif (offset >> 8) == 0x17
                  read_chips(offset)
                else
                  @data
                end
      end

      def poke(addr, value)
        @data = value
        offset = addr < 0x2000 || addr >= @mirror_end ? addr & 0x1fff : addr
        if offset < @low_end || offset >= 0x2000
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
