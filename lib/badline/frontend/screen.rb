# frozen_string_literal: true

module Badline
  module Frontend
    # The visible part of the video chip's display, the crop of the
    # machine's timing, repacked for an SDL texture in XRGB8888 in the
    # chip's palette, of 16 colours or the TED's 128. Spinel hands an Array
    # of Integers to C as 64-bit words, as badline/ffi does on CRuby, so
    # each word carries two neighbouring pixels, the left one in the low
    # half.
    #
    # Each pixel shows `pixel_width` of the window's square pixels wide,
    # or with `dots`, that many pixels share one, as the VDC's dots do. The
    # texture is as wide as the crop, an even number of pixels, and at
    # least MIN_WIDTH window pixels wide, and at least as high as PAL's C64
    # crop, 272 lines, so a C64 shows in the same window whatever its
    # region. A crop with fewer lines or pixels sits in the middle of the
    # texture, between black bands. The VIC-20's 284 by 284 crop and the
    # TED's 384 by 288 fill their own.
    #
    # With `frame_lines`, the crop's lines run on past the frame's last
    # line to its first, as the TED's do: its top border is the end of
    # the frame.
    class Screen
      MIN_WIDTH = Region::PAL.crop[2]
      MIN_HEIGHT = Region::PAL.crop[3]

      attr_reader :pixels, :width, :height

      def initialize(video, crop, pixel_width: 1, dots: 1, frame_lines: 0)
        @video = video
        @col_offset = crop[0]
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
        top = crop[1]
        wrap = frame_lines.zero? ? top + @lines : frame_lines
        @sources = Array.new(@lines) { |row| (row + top) % wrap }
        pair_up(video.palette)
        @pixels = Array.new(@height * @row_words, 0)
        pack_all
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
        sources = @sources
        row = 0
        while row < @lines
          pack_row(display, row) if dirty[sources[row]]
          row += 1
        end
        video.clear_dirty_lines!
      end

      private

      # The packed word for each pair of palette indices, the left one in
      # the low bits.
      def pair_up(palette)
        colors = palette.size
        shift = 4
        shift += 1 while (1 << shift) < colors
        mask = colors - 1
        @shift = shift
        @mask = mask
        @pairs = Array.new(colors << shift) { |pair| palette[pair & mask] | (palette[(pair >> shift) & mask] << 32) }
      end

      # Repacks every line, as a screen built for a display the chip has
      # already drawn starts with all of it.
      def pack_all
        display = @video.display
        row = 0
        while row < @lines
          pack_row(display, row)
          row += 1
        end
      end

      def pack_row(display, row)
        pixels = @pixels
        pairs = @pairs
        mask = @mask
        shift = @shift
        from = (@sources[row] * @stride) + @col_offset
        to = ((row + @band) * @row_words) + @margin
        last = to + @pair_count
        while to < last
          pixels[to] = pairs[(display[from] & mask) | ((display[from + 1] & mask) << shift)]
          from += 2
          to += 1
        end
      end
    end
  end
end
