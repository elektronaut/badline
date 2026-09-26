# frozen_string_literal: true

module Badline
  module Native
    # The visible part of the VIC's display, as GUI::ScreenPane crops it,
    # repacked for an SDL texture in XRGB8888. Spinel hands an Array of
    # Integers to C as 64-bit words, so each word carries two neighbouring
    # pixels, the left one in the low half.
    class Screen
      WIDTH = 384
      HEIGHT = 272
      COL_OFFSET = 96
      ROW_OFFSET = 20
      ROW_BYTES = WIDTH * 4

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
        @pixels = IO::Buffer.new(HEIGHT * ROW_BYTES)
      end

      # Repacks only the lines the VIC has changed since the last frame.
      def update
        dirty = @vic.dirty_lines
        row = 0
        while row < HEIGHT
          pack_row(row) if dirty[row + ROW_OFFSET]
          row += 1
        end
        @vic.clear_dirty_lines!
      end

      private

      def pack_row(row)
        display = @vic.display
        pixels = @pixels
        from = ((row + ROW_OFFSET) * @vic.width) + COL_OFFSET
        to = row * ROW_BYTES
        last = to + ROW_BYTES
        while to < last
          pixels.set_value(:u64, to, PAIRS[(display[from] & 0x0f) | ((display[from + 1] & 0x0f) << 4)])
          from += 2
          to += 8
        end
      end
    end
  end
end
