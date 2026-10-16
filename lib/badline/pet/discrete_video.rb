# frozen_string_literal: true

module Badline
  class PET
    # The 2001's and 3000 series' video, which runs at 60 Hz on every
    # board: 260 lines of 64 cycles, 16,640 cycles a frame. The first 200
    # lines show the 25 rows of characters, one character a cycle from
    # cycle FIRST_COLUMN of each line on, and the vertical drive line goes
    # low for the other 60, which the editor's IRQ fires on and its screen
    # writes wait for. xpet's 2001 and 3032 take 16,640 cycles from one
    # falling edge of the line to the next, and keep it low for 3,840.
    #
    # Each character reads its screen code from the 1K of screen RAM, as
    # it stands before the CPU's access that cycle, and its row from the
    # character ROM's half that VIA CA2 selects: graphics while CA2 is low,
    # text while it is high. The picture is the Canvas, DISPLAY_WIDTH by
    # DISPLAY_HEIGHT dots with the characters from (BORDER_LEFT,
    # BORDER_TOP) on, as xpet's screenshots frame it.
    class DiscreteVideo
      CYCLES_PER_LINE = 64
      LINES_PER_FRAME = 260
      DISPLAYED_LINES = 200
      COLUMNS = 40
      FIRST_COLUMN = 24
      DISPLAY_WIDTH = 384
      DISPLAY_HEIGHT = 217
      BORDER_LEFT = 32
      BORDER_TOP = 8

      attr_reader :column, :line, :canvas

      def initialize(cells, characters, via)
        @cells = cells
        @rows = characters.rows
        @via = via
        @canvas = Canvas.new(DISPLAY_WIDTH, DISPLAY_HEIGHT)
        @column = 0
        @line = 0
        @row_base = 0
        @row_line = 0
        @y = BORDER_TOP
        @shown = true
      end

      def cycle!
        column = @column
        fetch(column - FIRST_COLUMN) if column >= FIRST_COLUMN && @shown
        if column < CYCLES_PER_LINE - 1
          @column = column + 1
        else
          @column = 0
          next_line
        end
      end

      # The vertical drive line, high while the lines with characters show.
      def vertical_drive? = @shown

      private

      def fetch(char)
        set = @via.ca2_output ? Characters::TEXT : 0
        bits = @rows[set | (@cells[@row_base + char] << 3) | @row_line]
        @canvas.paint(BORDER_LEFT + (char << 3), @y, bits)
      end

      def next_line
        @line += 1
        @line = 0 if @line == LINES_PER_FRAME
        @row_line = @line & 0x07
        @row_base = (@line >> 3) * COLUMNS
        @y = BORDER_TOP + @line
        @shown = @line < DISPLAYED_LINES
      end
    end
  end
end
