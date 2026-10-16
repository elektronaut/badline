# frozen_string_literal: true

module Badline
  module Chips
    # The MOS 6545 CRTC, as the later PETs drive their screens with: an
    # address register at even addresses selects one of eighteen registers,
    # which the odd addresses write. Of them only the light pen's, R16 and
    # R17, and the cursor address, R14 and R15, read back; every other read
    # finds 0.
    #
    # Its counters run one character a cycle. A line is R0 + 1 characters,
    # a character row R9 + 1 lines, and a frame R4 + 1 rows and R5 lines of
    # vertical adjust. Vertical sync starts with row R7 and lasts 16 lines.
    # The picture it addresses isn't drawn yet.
    class CRTC
      # The bits each register keeps.
      MASKS = [0xff, 0xff, 0xff, 0xff, 0x7f, 0x1f, 0x7f, 0x7f, 0xff, 0x1f, 0x7f, 0x1f,
               0x3f, 0xff, 0x3f, 0xff, 0x3f, 0xff].freeze

      VSYNC_LINES = 16

      attr_reader :registers, :column, :line, :row

      def initialize
        @registers = Array.new(MASKS.length, 0)
        reset!
      end

      # The RES pin stops the counters at the start of a frame. The
      # registers keep their values.
      def reset!
        @selected = 0
        @column = 0
        @line = 0
        @row = 0
        @adjusting = false
        @vsync_lines = 0
      end

      # Whether vertical sync is on.
      def vsync? = @vsync_lines.positive?

      def peek(addr)
        return 0 if addr.nobits?(0x01) || @selected < 14 || @selected >= MASKS.length

        @registers[@selected]
      end

      def poke(addr, value)
        if addr.nobits?(0x01)
          @selected = value & 0x1f
        elsif @selected < MASKS.length
          @registers[@selected] = value & MASKS[@selected]
        end
      end

      def cycle!
        if @column < @registers[0]
          @column += 1
        else
          @column = 0
          next_line
        end
      end

      private

      def next_line
        @vsync_lines -= 1 if @vsync_lines.positive?
        if @adjusting
          @line += 1
          new_frame if @line >= @registers[5]
        elsif @line < @registers[9]
          @line += 1
        else
          next_row
        end
      end

      def next_row
        @line = 0
        if @row < @registers[4]
          @row += 1
          start_row
        elsif @registers[5].positive?
          @adjusting = true
        else
          new_frame
        end
      end

      def new_frame
        @line = 0
        @row = 0
        @adjusting = false
        start_row
      end

      def start_row
        @vsync_lines = VSYNC_LINES if @row == @registers[7]
      end
    end
  end
end
