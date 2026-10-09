# frozen_string_literal: true

module Badline
  class Drive1541
    # The disk turning under the Mechanism's head, and its read clock.
    #
    # The disk turns at 300 rpm, whatever the bit rate: once in 200 ms, or
    # 200,000 drive cycles. Each track's bits pass under the head at the
    # rate they were written at (see Track), and a 1 bit is a flux
    # transition at the start of its cell.
    #
    # The read circuit clocks bits out at the rate PB5-6 select, from a
    # counter the 16 MHz crystal steps every 16 - zone ticks. A flux
    # transition clears the counter. The counter clocks a bit into the
    # read shift register as it reaches 2 and every four steps after
    # that, and the bit is a 1 only for the first clock after the counter
    # passed 0. A bit is 4 * (16 - zone) ticks, so a byte takes 32, 30, 28
    # or 26 drive cycles in zones 0 to 3, and each transition brings the
    # clock back into step with the flux. A track read at the rate it was
    # written reads its bits. At another rate the clock and the cells
    # drift apart between transitions: a faster clock slips an extra 0
    # bit into some runs of 0 bits, a slower one drops one from some, and
    # the bytes come out garbled. Without flux the counter runs round on
    # its own and reads a 1 bit in every four.
    module Rotation
      CYCLE = 16 * Track::TICK

      # What the head reads with no disk in, or off the tracks a disk has:
      # no flux.
      BLANK = Track.new(Array.new(Disk::TRACK_LENGTHS[0], 0).freeze, 0)

      # One drive cycle: nothing with the motor off, and otherwise the
      # disk turns on by a cycle's ticks, 16 at 1 MHz and 8 at 2 MHz,
      # through whatever cells and clocks fall in them.
      def cycle!
        return unless @motor

        @time += @cycle_ticks
        pass_time if @time >= @next
      end

      private

      # The cell edges and clocks up to now, in the order they come. A
      # clock that falls on a cell edge comes after it.
      def pass_time
        while @cell_end <= @time || @clock_at <= @time
          if @cell_end <= @clock_at
            next_cell
          else
            clock
          end
        end
        @next = [@cell_end, @clock_at].min
      end

      # The head comes to the next cell, and a 1 bit's flux clears the
      # read clock while reading.
      def next_cell
        start = @cell_end
        @mask >>= 1
        start = next_byte(start) if @mask.zero?
        @cell_end = @index == @last && @mask == 1 ? Track::TURN : start + @width
        return if @writing || @bytes[@index].nobits?(@mask)

        @clock_at = start + (@clock / 2)
        @clocks = 0
      end

      # The head comes to the next byte, and at the end of the track back
      # round to the first, where the turn starts over.
      def next_byte(start)
        @mask = 0x80
        @index += 1
        if @index == @length
          @index = 0
          @time -= Track::TURN
          @clock_at -= Track::TURN
          start = 0
        end
        @width = @widths[@index] if @widths
        start
      end

      # The read clock ticks a bit into the shift register: a 1 the first
      # time after a flux transition or the counter's wrap.
      def clock
        at = @clock_at
        one = @clocks.zero?
        @clocks = (@clocks + 1) & 3
        @clock_at = at + @clock
        @writing ? write_bit(at) : read_bit(one)
      end

      # The track under the head and its layout, leaving the head's place
      # on it as it stands.
      def head_on_track
        @track = @disk&.track(surface) || BLANK
        @bytes = @track.bytes
        @widths = @track.widths
        @length = @track.length
        @last = @length - 1
      end

      # The track under the head, from the cell that's under it +time+
      # into the turn.
      def load_track(time = @time)
        @track = @disk&.track(surface) || BLANK
        @bytes = @track.bytes
        @widths = @track.widths
        @length = @track.length
        @last = @length - 1
        @index, @mask, @cell_end = @track.cell_at(time)
        @width = @widths ? @widths[@index] : @track.width
        @write_index = nil
        @track_written = false
        @next = [@cell_end, @clock_at].min
      end
    end
  end
end
