# frozen_string_literal: true

module Badline
  class VIC < Cycleable
    # = VIC-II display state
    #
    # The bad line condition, the video counters it drives, and the DMA it
    # starts. A condition that arrives mid-line opens the row late, which is
    # what makes the screen scroll sideways or lose a column of cells.
    class DisplayState
      FIRST_LINE = 0x30 # 48: bad lines and the DEN-at-$30 latch begin here
      LAST_LINE  = 0xf7 # 247
      COLUMNS_PER_ROW = 40

      # The last column of a rasterline already compares against the line
      # about to start, the same wrap the raster IRQ latch uses.
      WRAP_COLUMN = 62

      # BA goes low on the match; the VIC only owns the bus three cycles
      # later, when AEC follows. The row opens on that same edge.
      BA_DELAY = 3

      # Where a match pulls BA low, and where the c-accesses run.
      DMA_FIRST = 12
      DMA_LAST = 54
      FETCH_FIRST = 15

      # The row counter rewinds on a match standing in column 12, or on a
      # row opening late enough to still reach it. Derived against the
      # `dmadelay` tests, which sweep the match across the whole line.
      ROW_RESET_COLUMN = 12
      LATE_ROW_RESET_FIRST = 11
      LATE_ROW_RESET_LAST = 15

      attr_reader :vc_base, :vc, :vmli, :rc

      def initialize(registers)
        @registers = registers
        @vc_base = 0
        @vc = 0
        @vmli = 0
        @rc = 0
        @display = false
        @bad_lines_enabled = false
        @matched = false
        @opened = false
        @pending = nil
        @ba = nil
        new_line(0)
      end

      def display? = @display
      def idle? = !@display
      def bad_line? = !@ba.nil?

      # The bad line condition as it stands, without latching DEN.
      def bad_line_condition?
        @bad_lines_enabled && @in_window && @line_bits == @registers.yscroll
      end

      # True once AEC has followed BA down and the VIC owns the bus.
      def bus_taken?(column) = @ba ? column >= @ba + BA_DELAY : false

      # The c-accesses run from the match to the end of the fetch window. A
      # match so late that AEC would land past that window fetches nothing.
      def fetching?(column)
        ba = @ba
        return false if ba.nil? || ba + BA_DELAY > DMA_LAST

        column >= ba && column >= FETCH_FIRST && column <= DMA_LAST
      end

      def new_frame
        @vc_base = 0
        @bad_lines_enabled = false
      end

      def new_line(line)
        @opened = false
        @ba = nil
        @line_bits = line & 0b111
        @den_line = line == FIRST_LINE
        @in_window = line.between?(FIRST_LINE, LAST_LINE)
      end

      def cycle(rasterline, column)
        open_row(column) if @pending
        load_counters if column == 14

        match = column == WRAP_COLUMN ? wrap_match(rasterline + 1) : line_match
        match_bad_line(column) if match
        @matched = match
        check_row_counter(match) if column == 58
      end

      # A g-access in display state consumes one buffer cell and one video
      # matrix address. A row that opens mid-line makes fewer of them, and
      # the shortfall carries into VCBASE.
      def graphics_access
        @vc = (@vc + 1) & 0x3ff
        @vmli += 1
      end

      private

      def line_match
        latch_den if @den_line
        @bad_lines_enabled && @in_window && @line_bits == @registers.yscroll
      end

      # The wrap column compares against the line about to start. The DEN
      # latch is level-sensitive across the counter's increment, so this one
      # column sees both the line ending and the line starting.
      def wrap_match(line)
        latch_den if @den_line || line == FIRST_LINE
        return false unless line.between?(FIRST_LINE, LAST_LINE)

        @bad_lines_enabled && (line & 0b111) == @registers.yscroll
      end

      def latch_den
        @bad_lines_enabled = true if @registers.display_enabled?
      end

      # The condition is compared in every cycle, so a row can open from a
      # match the DMA window never sees. Only the leading edge opens one,
      # and only the first of a line: a match that outlives the row it
      # started, or trails it, does not open another.
      def match_bad_line(column)
        @rc = 0 if column == ROW_RESET_COLUMN
        @ba = column if @ba.nil? && column >= DMA_FIRST && column <= DMA_LAST
        return if @matched || @display || @opened

        @opened = true
        @pending = BA_DELAY
      end

      def open_row(column)
        @pending -= 1
        return unless @pending.zero?

        @pending = nil
        @display = true
        @rc = 0 if column.between?(LATE_ROW_RESET_FIRST, LATE_ROW_RESET_LAST)
      end

      def load_counters
        @vc = @vc_base
        @vmli = 0
      end

      # A condition still standing when the row counter wraps puts the logic
      # straight back into display state, so a forced row rolls into the
      # next one instead of leaving the line idle (Bauer 3.7.2 step 5).
      def check_row_counter(match)
        if @rc == 7
          @display = false
          @vc_base = @vc
        end
        @display ||= match
        @rc = (@rc + 1) & 0b111 if @display
      end
    end
  end
end
