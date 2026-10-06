# frozen_string_literal: true

module Badline
  class Vic20
    # The VIC-I, the 6561 on PAL machines: so far its sixteen registers
    # and its raster counter, without the video or the sound.
    #
    # The registers repeat through $9000-$90FF. $9003 bit 7 and $9004 read
    # the raster line, its bit 0 and bits 8-1. $9006 and $9007 read the
    # light pen, which nothing triggers yet, and $9008 and $9009 the two
    # pots, which read $FF with nothing plugged in. The other registers
    # read back what was written to them.
    class VIC
      CYCLES_PER_LINE = 71
      LINES_PER_FRAME = 312

      attr_reader :rasterline, :column

      def initialize
        power_on!
      end

      # The power-on state: the registers cleared and the raster at the top
      # of the frame. The VIC has no RES pin, so only power reaches it.
      def power_on!
        @registers = Array.new(16, 0)
        @rasterline = 0
        @column = 0
      end

      def cycle!
        @column += 1
        return if @column < CYCLES_PER_LINE

        @column = 0
        @rasterline += 1
        @rasterline = 0 if @rasterline == LINES_PER_FRAME
      end

      # The sixteen registers as written.
      def register_file = @registers.dup

      def peek(addr)
        register = addr & 0x0f
        case register
        when 0x03 then ((@rasterline & 0x01) << 7) | (@registers[3] & 0x7f)
        when 0x04 then @rasterline >> 1
        when 0x06, 0x07 then 0
        when 0x08, 0x09 then 0xff
        else @registers[register]
        end
      end

      def poke(addr, value)
        @registers[addr & 0x0f] = value
      end
    end
  end
end
