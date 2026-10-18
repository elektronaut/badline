# frozen_string_literal: true

require "badline/chips/crtc/keyed_state"

module Badline
  module Chips
    # The MOS 6545 CRTC, as the later PETs drive their screens with: an
    # address register at even addresses selects one of eighteen registers,
    # which the odd addresses write. Of them only the light pen's, R16 and
    # R17, and the cursor address, R14 and R15, read back; every other read
    # finds 0.
    #
    # Its counters run one character a cycle, and compare with the
    # registers as they stand that cycle, so a write lands from the next
    # character on:
    #
    # - The character counter runs from 0 to R0, then a line ends. The
    #   display shows from character 0 until the counter equals R1, and
    #   horizontal sync starts where it equals R2. A compare the counter has
    #   already passed doesn't happen that line: the display then runs on
    #   to the line's end.
    # - The line counter (RA, five bits) counts a character row's lines. A
    #   row ends after the line where it equals R9; past R9 it runs on to
    #   31 and wraps.
    # - The row counter (seven bits) counts rows to R4. R5 more lines of
    #   vertical adjust follow, then the frame starts again. The line
    #   counter counts them, and they end no row, past R9 or not. The display
    #   stops at the start of the row the counter equals R6, and comes back
    #   at the next frame; vertical sync starts with row R7 and lasts
    #   VSYNC_LINES lines.
    # - The memory address (MA, fourteen bits) starts each frame at
    #   R12:R13 and counts one a character. Each line starts again from its
    #   row's start, which the last line of a row moves on to the address
    #   where the counter equals R1.
    #
    # Each displayed character goes to the output's #character with MA, RA
    # and the characters since horizontal sync last started; the output
    # also hears of each #hsync as it starts, each #line_end, the
    # #rows_end where the display stops for the rest of the frame, and each
    # #frame_start.
    class CRTC
      # The bits each register keeps.
      MASKS = [0xff, 0xff, 0xff, 0xff, 0x7f, 0x1f, 0x7f, 0x7f, 0xff, 0x1f, 0x7f, 0x1f,
               0x3f, 0xff, 0x3f, 0xff, 0x3f, 0xff].freeze

      VSYNC_LINES = 16

      attr_reader :registers, :column, :line, :row, :address

      # The characters since horizontal sync last started.
      attr_reader :since_hsync

      # +registers+ is the register file, which the output may read too.
      def initialize(output, registers: Array.new(MASKS.length, 0))
        @output = output
        @registers = registers
        reset!
      end

      # The RES pin stops the counters at the start of a frame. The
      # registers keep their values.
      def reset!
        @selected = 0
        @column = 0
        @since_hsync = 0
        @vsync_lines = 0
        start_frame
      end

      # Whether vertical sync is on.
      def vsync? = @vsync_lines.positive?

      # Whether the display shows the character the counters are at.
      def display? = @row_display && @column_display

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
        regs = @registers
        column = @column
        if column == regs[1]
          @column_display = false
          @row_start = @address if @line == regs[9] && !@adjusting
        end
        @output.character(@address, @line, @since_hsync) if @column_display && @row_display
        if column == regs[2]
          @since_hsync = 1
          @output.hsync
        else
          @since_hsync += 1
        end
        @address = (@address + 1) & 0x3fff
        if column == regs[0]
          @column = 0
          end_line
        else
          @column = (column + 1) & 0xff
        end
      end

      private

      def end_line
        @output.line_end
        @vsync_lines -= 1 if @vsync_lines.positive?
        @column_display = true
        if @adjusting
          @line += 1
          @line >= @registers[5] ? start_frame : @address = @row_start
        elsif @line == @registers[9]
          end_row
        else
          @line = (@line + 1) & 0x1f
          @address = @row_start
        end
      end

      def end_row
        @line = 0
        if @row == @registers[4]
          return start_frame if @registers[5].zero?

          @adjusting = true
        else
          @row = (@row + 1) & 0x7f
          start_row
        end
        @address = @row_start
      end

      def start_frame
        @line = 0
        @row = 0
        @adjusting = false
        @row_display = true
        @column_display = true
        @row_start = ((@registers[12] << 8) | @registers[13]) & 0x3fff
        @address = @row_start
        start_row
        @output.frame_start
      end

      def start_row
        if @row == @registers[6] && @row_display
          @row_display = false
          @output.rows_end
        end
        @vsync_lines = VSYNC_LINES if @row == @registers[7]
      end
    end
  end
end
