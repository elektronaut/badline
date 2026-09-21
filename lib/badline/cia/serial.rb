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
    class Serial
      BITS = 8

      attr_reader :data, :sp_out, :cnt, :cnt_in
      attr_accessor :sp_in

      def initialize(control)
        @control = control
        @data = 0x0
        @shift = 0x0
        @steps = 0
        @pending = false
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
        @pending = true
      end

      # Clocked by timer A while transmitting. Yields once the last bit of a
      # byte has gone out.
      def underflow!
        return unless output?

        start if @steps.zero?
        return if @steps.zero?

        @steps -= 1
        @cnt = @steps.even?
        shift_out unless @cnt
        yield if @steps.zero? && block_given?
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
      # whichever side drives it now.
      def reset!
        @steps = 0
        @pending = false
        @cnt = output? || @cnt_in
      end

      private

      def start
        return unless @pending

        @pending = false
        @shift = @data
        @steps = BITS * 2
      end

      def shift_out
        @sp_out = @shift.anybits?(0x80)
        @shift = (@shift << 1) & 0xff
      end
    end
  end
end
