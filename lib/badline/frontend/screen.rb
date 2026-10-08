# frozen_string_literal: true

module Badline
  module Frontend
    # The visible part of the video chip's display, the crop of the
    # machine's timing, repacked for an SDL texture in XRGB8888 in the
    # chip's palette. Spinel hands an Array of Integers to C as 64-bit
    # words, as badline/ffi does on CRuby, so each word carries two
    # neighbouring pixels, the left one in the low half.
    #
    # Each pixel shows `pixel_width` of the window's square pixels wide,
    # or with `dots`, that many pixels share one, as the VDC's dots do. The
    # texture is as wide as the crop, an even number of pixels, and at
    # least MIN_WIDTH window pixels wide, and at least as high as PAL's C64
    # crop, 272 lines, so a C64 shows in the same window whatever its
    # region. A crop with fewer lines or pixels sits in the middle of the
    # texture, between black bands. The VIC-20's 284 by 284 crop fills its
    # own.
    class Screen
      MIN_WIDTH = Region::PAL.crop[2]
      MIN_HEIGHT = Region::PAL.crop[3]

      attr_reader :pixels, :width, :height

      def initialize(video, crop, pixel_width: 1, dots: 1)
        @video = video
        @col_offset = crop[0]
        @row_offset = crop[1]
        @lines = crop[3]
        @columns = crop[2] & ~1
        @pixel_width = pixel_width
        @dots = dots
        @stride = video.width.to_i
        @width = [@columns, ((MIN_WIDTH * dots / pixel_width) + 1) & ~1].max
        @height = [@lines, MIN_HEIGHT].max
        @row_words = @width / 2
        @pair_count = @columns / 2
        @margin = (@row_words - @pair_count) / 2
        @band = (@height - @lines) / 2
        palette = video.palette
        @pairs = Array.new(256) { |pair| palette[pair & 0x0f] | (palette[pair >> 4] << 32) }
        @pixels = Array.new(@height * @row_words, 0)
      end

      # The width in the window's square pixels.
      def window_width = @width * @pixel_width / @dots

      # The bytes of one row of the texture.
      def row_bytes = @width * 4

      # Repacks only the lines the chip has changed since the last frame.
      def update
        video = @video
        dirty = video.dirty_lines
        display = video.display
        row = 0
        while row < @lines
          pack_row(display, row) if dirty[row + @row_offset]
          row += 1
        end
        video.clear_dirty_lines!
      end

      private

      def pack_row(display, row)
        pixels = @pixels
        pairs = @pairs
        from = ((row + @row_offset) * @stride) + @col_offset
        to = ((row + @band) * @row_words) + @margin
        last = to + @pair_count
        while to < last
          pixels[to] = pairs[(display[from] & 0x0f) | ((display[from + 1] & 0x0f) << 4)]
          from += 2
          to += 1
        end
      end
    end
  end
end
