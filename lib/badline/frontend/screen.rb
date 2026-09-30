# frozen_string_literal: true

module Badline
  module Frontend
    # The visible part of the VIC's display, the crop of the machine's
    # region, repacked for an SDL texture in XRGB8888. Spinel hands an
    # Array of Integers to C as 64-bit words, as badline/ffi does on CRuby,
    # so each word carries two neighbouring pixels, the left one in the low
    # half. The texture is PAL's crop, 384x272, and a region with fewer
    # lines to show sits in the middle of it, between black bands.
    class Screen
      WIDTH = Region::PAL.crop[2]
      HEIGHT = Region::PAL.crop[3]
      ROW_BYTES = WIDTH * 4
      ROW_WORDS = WIDTH / 2

      COLORS = [
        0x000000, 0xffffff, 0x924a40, 0x84c5cc,
        0x9351b6, 0x72b14b, 0x483aaa, 0xd5df7c,
        0x675200, 0xc33d00, 0xc18178, 0x606060,
        0x8a8a8a, 0xb3ec91, 0x867ade, 0xb3b3b3
      ].freeze

      PAIRS = Array.new(256) { |pair| COLORS[pair & 0x0f] | (COLORS[pair >> 4] << 32) }.freeze

      attr_reader :pixels

      def initialize(vic)
        @vic = vic
        crop = vic.region.crop
        @col_offset = crop[0]
        @row_offset = crop[1]
        @height = crop[3]
        @band = (HEIGHT - @height) / 2
        @pixels = Array.new(HEIGHT * ROW_WORDS, 0)
      end

      # Repacks only the lines the VIC has changed since the last frame.
      def update
        dirty = @vic.dirty_lines
        row = 0
        while row < @height
          pack_row(row) if dirty[row + @row_offset]
          row += 1
        end
        @vic.clear_dirty_lines!
      end

      private

      def pack_row(row)
        display = @vic.display
        pixels = @pixels
        from = ((row + @row_offset) * @vic.width) + @col_offset
        to = (row + @band) * ROW_WORDS
        last = to + ROW_WORDS
        while to < last
          pixels[to] = PAIRS[(display[from] & 0x0f) | ((display[from + 1] & 0x0f) << 4)]
          from += 2
          to += 1
        end
      end
    end
  end
end
