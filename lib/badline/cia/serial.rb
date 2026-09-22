# frozen_string_literal: true

module Badline
  class CIA
    # The serial shift register and the CNT line that clocks it.
    #
    # With CRA bit 6 clear the port is an input: SP is sampled on every
    # rising CNT edge, and the byte reaches the data register after eight of
    # them. With the bit set the CIA drives CNT itself, toggling it on every
    # timer A underflow, so a byte takes sixteen underflows to go out. CNT falls
    # as each bit is put on SP, and rises again to clock it in.
    #
    # The register counts itself empty as soon as the eighth bit is on SP,
    # fifteen underflows in: the serial flag follows a few cycles later
    # rather than waiting for the sixteenth underflow, and a byte written
    # from that point on goes out on the next one.
    class Serial
      BITS = 8

      # A byte written to the data register reaches the shift register one
      # cycle later. The empty countdown starts on the underflow that puts
      # the eighth bit on SP and is decremented on that same cycle, so the
      # flag lands four cycles after it.
      LOAD_DELAY = 1
      EMPTY_DELAY = 5
      BUSY_DELAY = 5

      # The logic watching the shift register runs a few cycles behind it,
      # so the level saying a bit is still on its way out is scheduled
      # through a delay line: a bit set at position 7 - n takes effect n
      # cycles later. Putting a bit on SP raises the level after one cycle
      # and drops it again after two before raising it for good after
      # three; the eighth bit skips straight to the last of those. CNT
      # rising over a bit lowers the level four cycles later.
      IN_FLIGHT = 0x50
      LAST_IN_FLIGHT = 0x10
      BOUNCE = 0x20
      SETTLED = 0x08

      attr_reader :data, :sp_out, :cnt, :cnt_in
      attr_accessor :sp_in

      def initialize(control)
        @control = control
        @data = 0x0
        @shift = 0x0
        @steps = 0
        @empty_in = nil
        @busy_in = nil
        @busy = false
        @abandoned = false
        @pending = nil
        @underflow_high = false
        @in_flight = false
        @flight_up = 0x0
        @flight_down = 0x0
        @idle = true
        # Nothing drives the user port, so both lines float high.
        @cnt = true
        @cnt_in = true
        @sp_in = true
        @sp_out = true
      end

      def output?
        @control.serial_mode?
      end

      def cnt_in=(level)
        @cnt_in = level
        @cnt = level unless output?
      end

      def write(value)
        @data = value
        @pending = LOAD_DELAY
        @idle = false
      end

      # Clocked every cycle with timer A's underflow line. Yields once the
      # shift register reports itself empty, which it does without waiting
      # for the underflow that raises CNT over the eighth bit.
      def cycle!(underflowed)
        if @idle && !underflowed
          @underflow_high = false
          return
        end

        shift(underflowed)
        @pending -= 1 if @pending&.positive?
        drain_flight
        count_busy
        @idle = idle?
        return if @empty_in.nil?

        @empty_in -= 1
        return unless @empty_in.zero?

        @empty_in = nil
        @busy = false
        yield
      end

      # Clocked by rising CNT edges while receiving. Yields once a whole
      # byte has arrived.
      def rising_edge!
        return if output?

        @shift = ((@shift << 1) | (@sp_in ? 1 : 0)) & 0xff
        @steps += 1
        return unless @steps == BITS

        @steps = 0
        @data = @shift
        yield if block_given?
      end

      # A mode change drops the byte in flight and hands CNT back to
      # whichever side drives it now, and yields: that byte counts as gone.
      # Handing the port over as an input tears a transmission down, so a
      # busy register reports it; the same change latches how far the bit
      # in flight had got, and taking the port back reports that.
      def reset!
        abandoned = output? ? @abandoned : @busy
        @abandoned = output? ? false : @in_flight
        @in_flight = false
        @steps = 0
        @empty_in = nil
        @busy_in = nil
        @busy = false
        @pending = nil
        @cnt = output? || @cnt_in
        yield if abandoned
      end

      private

      # Without an underflow, a register with nothing counting down and
      # nothing in the delay lines has nothing to do on a cycle.
      def idle?
        !@pending&.positive? && (@flight_up | @flight_down).zero? &&
          @busy_in.nil? && @empty_in.nil?
      end

      # The shift register picks up a waiting byte whenever the underflow
      # line is asserted, but every half-step after that needs a fresh edge
      # on it. A zero latch holds the line down for good rather than
      # pulsing it, so such a byte stops after its first bit and never
      # reaches the data register.
      def shift(underflowed)
        edge = underflowed && !@underflow_high
        @underflow_high = underflowed
        clock(edge) if underflowed && output?
      end

      def clock(edge)
        start if @steps <= 1
        if @steps.zero?
          @flight_down |= SETTLED
        elsif edge || @steps == BITS * 2
          half_step
        end
      end

      def half_step
        @steps -= 1
        @cnt = @steps.even?
        if @cnt
          @flight_down |= SETTLED
        else
          shift_out
        end
      end

      # The register reads as busy from a few cycles after the first bit
      # reaches SP until it reports itself empty over the eighth.
      def mark_busy
        case @steps
        when (BITS * 2) - 1 then @busy_in = BUSY_DELAY
        when 1
          @empty_in = EMPTY_DELAY
          @busy_in = nil
        end
      end

      def count_busy
        return if @busy_in.nil?

        @busy_in -= 1
        return unless @busy_in.zero?

        @busy_in = nil
        @busy = true
      end

      def drain_flight
        @in_flight = false if @flight_down.anybits?(0x80)
        @flight_down = (@flight_down << 1) & 0xff
        @in_flight = true if @flight_up.anybits?(0x80)
        @flight_up = (@flight_up << 1) & 0xff
      end

      # A byte only moves out of the data register once the one before it
      # has put its last bit on SP.
      def start
        return unless @pending&.zero?

        @pending = nil
        @shift = @data
        @steps = BITS * 2
      end

      def shift_out
        @sp_out = @shift.anybits?(0x80)
        @shift = (@shift << 1) & 0xff
        mark_busy
        @flight_up |= @steps == 1 ? LAST_IN_FLIGHT : IN_FLIGHT
        @flight_down |= BOUNCE
      end
    end
  end
end
