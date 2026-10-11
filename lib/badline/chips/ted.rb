# frozen_string_literal: true

require "badline/chips/ted/timers"
require "badline/chips/ted/beam"
require "badline/chips/ted/fetches"
require "badline/chips/ted/palette"
require "badline/chips/ted/modes"
require "badline/chips/ted/picture"

module Badline
  module Chips
    # The TED of the Commodore 264 series, the 7360 and 8360: its registers
    # at $FF00-$FF1F, the raster, the three timers, the interrupt, the
    # keyboard latch, the clock it gives the CPU (Beam), what it fetches
    # for the picture (Fetches) and the picture (Picture). It plays no
    # sound yet: those registers keep what is written to them.
    #
    # The machine clocks it once a single clock cycle, 57 to a line, and
    # asks it then how many cycles the CPU runs in that one (#cpu_slots)
    # and whether BA is low (#ba_low?).
    #
    # $FF08 is the keyboard latch: a write latches the K0-K7 inputs, which
    # the keyboard port answers for the byte written (KeyboardPort#latch),
    # and a read returns them. $FF09 holds the interrupt flags, each
    # cleared by writing a 1 to it, with bit 7 set while the interrupt
    # line is pulled. $FF0A holds the mask and bit 8 of the raster compare,
    # and $FF0B the compare's low byte. $FF13 bit 0 reads whether the CPU
    # sees ROM at $8000-$FFFF (#rom_selected=). $FF1C and $FF1D read and
    # set the raster line, and $FF1E reads the horizontal position's top 8
    # bits. $FF1A and $FF1B read and set the character position reload,
    # and $FF1F the row's line in bits 0-2 and in bits 3-6 the blink
    # counter, which counts frames.
    class TED
      include Timers
      include Beam
      include Fetches
      include Palette
      include Modes
      include Picture

      # The clock a TED is fed, its single clock: the crystal divided by 20
      # on PAL machines and by 16 on NTSC ones (the Plus/4 hardware manual's
      # TED datasheet).
      Profile = Data.define(:name, :clock_hz)

      PAL = Profile.new(name: :pal, clock_hz: 886_724)
      NTSC = Profile.new(name: :ntsc, clock_hz: 894_886)

      RASTER_FLAG = 0x02

      # The interrupt sources a mask bit can enable: the raster, the light
      # pen and the three timers.
      SOURCES = 0x5e

      # The registers the picture reads as it paints: $FF06, $FF07, the
      # cursor and the five colours.
      PICTURE_REGISTERS = 0x03e030c0

      attr_reader :profile, :interrupt_flags, :interrupt_mask

      # What answers the keyboard latch: an object with #latch(value).
      attr_writer :keyboard_port

      # Whether the CPU sees ROM at $8000-$FFFF, which $FF13 bit 0 reads.
      attr_writer :rom_selected

      def initialize(profile = PAL)
        @profile = profile
        @keyboard_port = nil
        @rom_selected = true
        @bus = nil
        power_on!
      end

      def power_on!
        @registers = Array.new(0x20, 0)
        @interrupt_flags = 0
        @interrupt_mask = 0
        @raster_compare = 0
        @key_latch = 0xff
        @blink = 0
        reset_timers
        reset_fetches
        reset_picture
        reset_beam
      end

      # Counts the timers, moves the beam on a cycle and makes the cycle's
      # fetches, unless $FF07's freeze bit holds them, then decides the
      # CPU's clock for the cycle.
      def cycle!
        unless frozen?
          count_timers
          move_beam
          fetch(@column)
          picture_cycle(@column)
        end
        decide_clock
      end

      # Whether the interrupt line is pulled: a flag raised whose mask bit
      # is set.
      def irq? = @interrupt_flags.anybits?(@interrupt_mask & SOURCES)

      def peek(addr)
        register = addr & 0x3f
        return 0xff if register >= 0x20

        case register
        when 0x00..0x05 then read_timer(register)
        when 0x08 then @key_latch
        when 0x09 then read_interrupt_flags
        when 0x0a then @interrupt_mask | 0xa0
        when 0x0b then @raster_compare & 0xff
        when 0x13 then (@registers[0x13] & 0xfe) | (@rom_selected ? 1 : 0)
        when 0x1a then 0xfc | (@char_position >> 8)
        when 0x1b then @char_position & 0xff
        when 0x1c then 0xfe | (@line >> 8)
        when 0x1d then @line & 0xff
        when 0x1e then @column << 2
        when 0x1f then 0x80 | (@blink << 3) | @row_line
        else @registers[register]
        end
      end

      def poke(addr, value)
        register = addr & 0x3f
        return if register >= 0x20

        paint_to_write if (PICTURE_REGISTERS >> register).anybits?(1)
        @registers[register] = value
        case register
        when 0x00..0x05 then write_timer(register, value)
        when 0x08 then @key_latch = @keyboard_port ? @keyboard_port.latch(value) : 0xff
        when 0x09 then @interrupt_flags &= ~value
        when 0x0a then write_interrupt_mask(value)
        when 0x0b then @raster_compare = (@raster_compare & 0x100) | value
        when 0x1a then @char_position = (@char_position & 0xff) | ((value & 0x03) << 8)
        when 0x1b then @char_position = (@char_position & 0x300) | value
        when 0x1c then self.line = (@line & 0xff) | ((value & 0x01) << 8)
        when 0x1d then self.line = (@line & 0x100) | value
        when 0x1f then write_row_line(value)
        end
      end

      private

      # $FF07 bit 5 stops the beam and the timers.
      def frozen? = @registers[0x07].anybits?(0x20)

      def read_interrupt_flags
        value = @interrupt_flags | 0x21
        irq? ? value | 0x80 : value
      end

      def write_row_line(value)
        @row_line = value & 0x07
        @blink = (value >> 3) & 0x0f
      end

      # The end of a frame: the fetches' counters start over.
      def end_frame
        end_fetch_frame
        end_picture_frame
      end

      def write_interrupt_mask(value)
        @interrupt_mask = value & 0x5f
        @raster_compare = (@raster_compare & 0xff) | ((value & 0x01) << 8)
      end

      def line=(value)
        @line = value
        raster_reached
      end

      def raster_reached
        @interrupt_flags |= RASTER_FLAG if @line == @raster_compare
      end
    end
  end
end
