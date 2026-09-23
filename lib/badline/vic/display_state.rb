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

      # AEC follows BA three cycles later; the c-accesses before it read
      # the bus the CPU still drives.
      BA_DELAY = 3

      # Columns run two ahead of Bauer's cycle numbers: column 10 is his
      # cycle 12. BA falls on a match in columns 10-52, the c-accesses run
      # in 13-52 and the g-accesses in 14-53. VC and VMLI reload in column
      # 12 and the row counter steps in column 56.
      DMA_FIRST = 10
      DMA_LAST = 52
      FETCH_FIRST = 13
      GRAPHICS_FIRST = 14
      GRAPHICS_LAST = 53
      LOAD_COLUMN = 12
      RC_COLUMN = 56

      GRAPHICS_COLUMNS = Array.new(63) { |column| column.between?(GRAPHICS_FIRST, GRAPHICS_LAST) }.freeze

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
        @ba = nil
        new_line(0)
      end

      def display? = @display
      def idle? = !@display
      def bad_line? = !@ba.nil?

      # The bad line condition as the last column compared it.
      def bad_line_condition? = @matched

      # True once AEC has followed BA down and the VIC owns the bus.
      def bus_taken?(column) = @ba ? column >= @ba + BA_DELAY : false

      def fetching?(column)
        @matched && column >= FETCH_FIRST && column <= DMA_LAST
      end

      def new_frame
        @vc_base = 0
        @bad_lines_enabled = false
      end

      def new_line(line)
        @ba = nil
        @line_bits = line & 0b111
        @den_line = line == FIRST_LINE
        @in_window = line.between?(FIRST_LINE, LAST_LINE)
      end

      def cycle(rasterline, column)
        match = column == WRAP_COLUMN ? wrap_match(rasterline + 1) : line_match
        @matched = match
        if match
          @display = true
          @ba = column if @ba.nil? && column >= DMA_FIRST && column <= DMA_LAST
        end
        load_counters(match) if column == LOAD_COLUMN
        check_row_counter(match) if column == RC_COLUMN
      end

      # A g-access in display state consumes one buffer cell and one video
      # matrix address. A row that opens mid-line makes fewer of them, and
      # the shortfall carries into VCBASE.
      def graphics_column?(column) = GRAPHICS_COLUMNS[column]

      def graphics_access(column)
        return unless graphics_column?(column)

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

      def load_counters(match)
        @vc = @vc_base
        @vmli = 0
        @rc = 0 if match
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
