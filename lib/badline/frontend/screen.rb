# frozen_string_literal: true

module Badline
  module Frontend
    # The visible part of the video chip's display, the crop of the
    # machine's timing, repacked for an SDL texture in XRGB8888 in the
    # chip's palette. Spinel hands an Array of Integers to C as 64-bit
    # words, as badline/ffi does on CRuby, so each word carries two
    # neighbouring pixels, the left one in the low half. The texture is
    # PAL's crop, 384x272, and a crop with fewer lines sits in the middle
    # of it, between black bands.
    class Screen
      WIDTH = Region::PAL.crop[2]
      HEIGHT = Region::PAL.crop[3]
      ROW_BYTES = WIDTH * 4
      ROW_WORDS = WIDTH / 2

      attr_reader :pixels

      def initialize(video, crop)
        @video = video
        @col_offset = crop[0]
        @row_offset = crop[1]
        @height = crop[3]
        @band = (HEIGHT - @height) / 2
        palette = video.palette
        @pairs = Array.new(256) { |pair| palette[pair & 0x0f] | (palette[pair >> 4] << 32) }
        @pixels = Array.new(HEIGHT * ROW_WORDS, 0)
      end

      # Repacks only the lines the chip has changed since the last frame.
      def update
        video = @video
        dirty = video.dirty_lines
        display = video.display
        width = video.width
        row = 0
        while row < @height
          pack_row(display, width, row) if dirty[row + @row_offset]
          row += 1
        end
        video.clear_dirty_lines!
      end

      private

      def pack_row(display, width, row)
        pixels = @pixels
        pairs = @pairs
        from = ((row + @row_offset) * width) + @col_offset
        to = (row + @band) * ROW_WORDS
        last = to + ROW_WORDS
        while to < last
          pixels[to] = pairs[(display[from] & 0x0f) | ((display[from + 1] & 0x0f) << 4)]
          from += 2
          to += 1
        end
      end
    end
  end
end
