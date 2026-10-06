# frozen_string_literal: true

module Badline
  module Frontend
    # The visible part of the video chip's display, the crop of the
    # machine's timing, repacked for an SDL texture in XRGB8888 in the
    # chip's palette. Spinel hands an Array of Integers to C as 64-bit
    # words, as badline/ffi does on CRuby, so each word carries two
    # neighbouring pixels, the left one in the low half.
    #
    # The texture is as wide as the crop and at least as high as PAL's
    # C64 crop, 272 lines, so a C64 shows in the same window whatever its
    # region: a crop with fewer lines sits in the middle of the texture,
    # between black bands. The VIC-20's 284 by 284 crop fills its own.
    class Screen
      MIN_HEIGHT = Region::PAL.crop[3]

      attr_reader :pixels, :width, :height

      def initialize(video, crop)
        @video = video
        @col_offset = crop[0]
        @row_offset = crop[1]
        @lines = crop[3]
        @width = crop[2]
        @stride = video.width.to_i
        @height = [@lines, MIN_HEIGHT].max
        @row_words = @width / 2
        @band = (@height - @lines) / 2
        palette = video.palette
        @pairs = Array.new(256) { |pair| palette[pair & 0x0f] | (palette[pair >> 4] << 32) }
        @pixels = Array.new(@height * @row_words, 0)
      end

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
        to = (row + @band) * @row_words
        last = to + @row_words
        while to < last
          pixels[to] = pairs[(display[from] & 0x0f) | ((display[from + 1] & 0x0f) << 4)]
          from += 2
          to += 1
        end
      end
    end
  end
end
