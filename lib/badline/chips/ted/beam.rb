# frozen_string_literal: true

module Badline
  module Chips
    class TED
      # The raster and the clock the TED gives the CPU, a single clock
      # cycle at a time.
      #
      # A line is 456 dots, horizontal counts 0-455, and a single clock
      # cycle 8 of them, so a line is 57 cycles; #column counts them, the
      # cycle at count 8 * column. The line count steps at count 376, in
      # column 47, and runs 0-311 on PAL and 0-261 with $FF07 bit 6 set
      # (NTSC). The datasheet's horizontal and vertical decode tables give
      # those counts.
      #
      # The CPU runs once in a single clock cycle and twice in a double
      # clock one. The datasheet's "System Clock Doubling": in the display
      # window's lines the clock is single from count 400 round to 344,
      # columns 50-56 and 0-42, and double in columns 43-49. The window is
      # lines 0-203: the datasheet says 0-204, but xplus4 runs line 204 at
      # double clock, as the lines below it. In the other lines it is double
      # but for the five refresh cycles at counts 304-344, columns 38-42,
      # which are single everywhere. With $FF06 bit 4 clear (blank) every
      # line is double but for refresh, and $FF13 bit 1 or $FF07 bit 5
      # (freeze) makes every cycle single.
      #
      # So a display line gives the CPU 64 cycles and a border line 109,
      # the counts measured on real machines.
      #
      # DMA: each character row takes the bus for 40 cycles on two lines,
      # the line before the row for the attributes and the row's first
      # line for the character pointers (the datasheet's register 20). A
      # row starts on the line after one whose low three bits match $FF06
      # bits 0-2, as the KERNAL's scroll of 3 puts the first row on line 4,
      # where the datasheet's 25-row window starts, and a row starts only
      # in lines 0-203. xplus4 takes the bus on the same lines. The fetches run in columns 54-56 and 0-36, and BA
      # goes low 3 cycles before the first, in column 51, so the CPU stops
      # at its next read. A DMA line leaves the CPU 24 cycles.
      module Beam
        CYCLES_PER_LINE = 57
        LINE_STEP_COLUMN = 47
        BA_COLUMN = 51
        DMA_COLUMN = 54
        DMA_END_COLUMN = 36
        REFRESH_COLUMNS = (38..42)
        DOUBLE_COLUMNS = (43..49)
        LAST_DISPLAY_LINE = 203

        # The DMA a line makes: none, the attributes or the pointers.
        NO_DMA = 0
        ATTRIBUTE_DMA = 1
        POINTER_DMA = 2

        # The single clock cycle in the line, 0-56.
        attr_reader :column

        # The raster line.
        attr_reader :line

        # How many cycles the CPU runs in this cycle: 0 while the TED holds
        # the bus for DMA, 1 at single clock and 2 at double clock.
        attr_reader :cpu_slots

        # Whether BA is low, from 3 cycles before DMA to its end.
        def ba_low? = @ba_low

        # Lines a frame, by $FF07 bit 6.
        def lines_per_frame = @registers[0x07].anybits?(0x40) ? 262 : 312

        private

        def reset_beam
          @column = 0
          @line = 0
          @ba_low = false
          @cpu_slots = 1
        end

        def move_beam
          column = @column + 1
          column = 0 if column == CYCLES_PER_LINE
          @column = column
          return unless column == LINE_STEP_COLUMN

          line = @line + 1
          if line >= lines_per_frame
            line = 0
            end_frame
          end
          step_row_line(line)
          step_scanline(line)
          self.line = line
        end

        # The clock for the cycle. Freeze leaves single clock, without DMA.
        def decide_clock
          column = @column
          if @dma_kind != NO_DMA && (column >= BA_COLUMN || column <= DMA_END_COLUMN) && !frozen?
            @ba_low = true
            @cpu_slots = column >= DMA_COLUMN || column <= DMA_END_COLUMN ? 0 : 1
            return
          end

          @ba_low = false
          @cpu_slots = single_clock?(column) ? 1 : 2
        end

        def single_clock?(column)
          return true if REFRESH_COLUMNS.include?(column) || @registers[0x13].anybits?(0x02) || frozen?

          display_window? && !DOUBLE_COLUMNS.include?(column)
        end

        def display_window? = @registers[0x06].anybits?(0x10) && @line <= LAST_DISPLAY_LINE
      end
    end
  end
end
