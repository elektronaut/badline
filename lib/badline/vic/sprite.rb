# frozen_string_literal: true

module Badline
  class VIC < Cycleable
    class Sprite
      X_OFFSET = 104
      ROWS = 21

      attr_reader :index, :line_pixels

      def initialize(index, registers, bank, width)
        @index = index
        @registers = registers
        @bank = bank
        @width = width
        @bit = 1 << index
        @displaying = false
        @display_on = false
        @counter = 0
        @bits = nil
        @line_pixels = nil
        @leftmost = nil
        @pixel_buffer = Array.new(48)
      end

      def displaying? = @displaying

      def enabled? = @registers[0x15].anybits?(@bit)
      def multicolor?(view = @registers) = view[0x1c].anybits?(@bit)
      def x_expanded? = @registers[0x1d].anybits?(@bit)
      def y_expanded? = @registers[0x17].anybits?(@bit)
      def priority?(view = @registers) = view[0x1b].anybits?(@bit)

      def x
        msb = @registers[0x10].anybits?(@bit) ? 0x100 : 0
        msb | @registers[index * 2]
      end

      def y = @registers[(index * 2) + 1]
      def color(view = @registers) = view[0x27 + index] & 0x0f

      # X is latched per line when the row is decoded; a write after that
      # point moves the sprite from the next line on.
      def leftmost = @leftmost || ((x + X_OFFSET) % @width)
      def pixel_width = x_expanded? ? 48 : 24

      # The Y/enable compare runs at cycles 55/56 of each line; a match turns
      # DMA on. Display is enabled separately in cycle 58, so the rows render
      # from the following line on.
      def check_dma(line)
        return if @displaying || !enabled? || line != y

        @displaying = true
        @display_on = false
        @counter = 0
      end

      # Cycle 58: a sprite with DMA running starts (or resumes) displaying
      # only while Y still matches the raster line, so a Y write landing
      # between the compares keeps the data fetch running invisibly.
      def check_display(line)
        @display_on = true if @displaying && line == y
      end

      def start_line
        return @line_pixels = nil unless @displaying

        row = y_expanded? ? @counter / 2 : @counter
        if row >= ROWS
          @displaying = false
          return @line_pixels = nil
        end

        @counter += 1
        return @line_pixels = nil unless @display_on

        @leftmost = (x + X_OFFSET) % @width
        fetch(row)
        decode_line
      end

      def pixel(raster_x)
        return nil unless @line_pixels

        dist = raster_x - leftmost
        dist += @width if dist.negative?
        dist < pixel_width ? @line_pixels[dist] : nil
      end

      # Rebuild the line buffer against a mid-line register view, so
      # segmented compositing can splice in state changes.
      def redecode(view)
        decode_line(view)
      end

      private

      # Decode the fetched 24 data bits into a buffer of pixel colors (nil is
      # transparent), so compositing can read pixels without re-deriving them.
      def decode_line(view = @registers, pixels = @pixel_buffer)
        @line_pixels = pixels
        if multicolor?(view)
          decode_multicolor(pixels, x_expanded?, view)
        else
          decode_hires(pixels, x_expanded?, view)
        end
      end

      def decode_hires(pixels, expanded, view)
        own = color(view)
        last = expanded ? 48 : 24
        i = 0
        while i < last
          offset = expanded ? i >> 1 : i
          pixels[i] = (@bits >> (23 - offset)).anybits?(1) ? own : nil
          i += 1
        end
      end

      def decode_multicolor(pixels, expanded, view)
        shared1 = view[0x25] & 0x0f
        shared2 = view[0x26] & 0x0f
        own = color(view)
        last = expanded ? 48 : 24
        i = 0
        while i < last
          offset = expanded ? i >> 1 : i
          pixels[i] = case (@bits >> (22 - (offset & ~1))) & 0b11
                      when 0b01 then shared1
                      when 0b10 then own
                      when 0b11 then shared2
                      end
          i += 1
        end
      end

      def fetch(row)
        base = (pointer * 64) + (row * 3)
        @bits = (@bank.peek(base) << 16) |
                (@bank.peek(base + 1) << 8) |
                @bank.peek(base + 2)
      end

      def pointer = @bank.peek(@registers.screen_base + 0x3f8 + index)
    end
  end
end
