# frozen_string_literal: true

module Badline
  class PET
    # The counters of the 2001's and 3000 series' video, which runs at 60
    # Hz on every board: 260 lines of 64 cycles, 16,640 cycles a frame,
    # about what xpet's 2001 and 3032 take between two retrace edges. The
    # first 200 lines show the 25 rows of characters, and the vertical
    # drive line goes low for the other 60, which the editor's IRQ fires
    # on and its screen writes wait for. The picture isn't drawn yet.
    class DiscreteVideo
      CYCLES_PER_LINE = 64
      LINES_PER_FRAME = 260
      DISPLAYED_LINES = 200

      attr_reader :column, :line

      def initialize
        @column = 0
        @line = 0
      end

      def cycle!
        @column += 1
        return if @column < CYCLES_PER_LINE

        @column = 0
        @line += 1
        @line = 0 if @line == LINES_PER_FRAME
      end

      # The vertical drive line, high while the lines with characters show.
      def vertical_drive? = @line < DISPLAYED_LINES
    end
  end
end
