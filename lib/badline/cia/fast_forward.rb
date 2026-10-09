# frozen_string_literal: true

module Badline
  class CIA
    # Running a CIA a stretch of cycles at once, for Drive::Idle.
    module FastForward
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

      # Runs +cycles+ cycles at once while quiet?, as cycle! would: timer A's
      # underflows flag in the ICR, and reach the serial port's underflow
      # line.
      def fast_forward(cycles)
        @tod.fast_forward(cycles)
        return if @ta.idle?

        @icr.flag(:timer_a) if @ta.fast_forward(cycles).positive?
        @serial.follow_underflow(@ta.underflowed)
      end

      private

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
