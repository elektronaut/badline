# frozen_string_literal: true

module Badline
  class CIA
    # Running a CIA a stretch of cycles at once, for Drive::Idle.
    module FastForward
      # quiet_cycles for a CIA whose counters will never set a flag.
      QUIET = 1 << 40

      # Whether fast_forward can run the CIA: timer B stopped with nothing
      # in its pipeline, no interrupt or acknowledge on its way, CNT where it
      # was, the TOD clock stopped, and timer A either stopped, or free
      # running (Timer#free_running?) with its interrupt masked and the
      # serial port an idle input. Drive::Idle sleeps the 1571's CIA through
      # such cycles, which its DOS leaves timer A running in.
      def quiet?
        return false unless @tb.idle? && @icr.quiet && @tod.quiet? && cnt_steady?

        @ta.idle? ? @serial.idle : timer_a_free_running?
      end

      # How many cycles the CIA can run with nothing but its counters
      # moving: as quiet? allows, but with timer B free running too, up to
      # the cycle before it underflows. The 1581's DOS leaves timer B
      # interrupting every 10 ms.
      def quiet_cycles
        return 0 unless @icr.quiet && @tod.quiet? && cnt_steady? && timer_a_quiet?
        return QUIET if @tb.idle?
        return 0 unless @tb.free_running? && @control_b.value.nobits?(0x60)

        @tb.counter - 1
      end

      # Runs +cycles+ cycles at once while quiet? or for quiet_cycles, as
      # cycle! would: timer A's underflows flag in the ICR, and reach the
      # serial port's underflow line.
      def fast_forward(cycles)
        @tod.fast_forward(cycles)
        @tb.fast_forward(cycles) unless @tb.idle?
        return if @ta.idle?

        @icr.flag(:timer_a) if @ta.fast_forward(cycles).positive?
        @serial.follow_underflow(@ta.underflowed)
      end

      private

      def timer_a_quiet? = @ta.idle? ? @serial.idle : timer_a_free_running?

      # Timer A free running with its interrupt masked, and the serial port
      # an idle input it only clocks.
      def timer_a_free_running?
        @ta.free_running? && !@control_a.serial_mode? && @icr.mask.value.nobits?(0x01) && @serial.drained?
      end

      # Whether CNT holds the level the last cycle sampled.
      def cnt_steady? = @serial.cnt == @cnt_high && !@cnt_rise
    end
  end
end
