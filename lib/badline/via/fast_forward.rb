# frozen_string_literal: true

module Badline
  class VIA
    # Running a VIA a stretch of cycles at once while nothing but its
    # counters would change, for Drive1541::Idle.
    module FastForward
      # quiet_cycles for a VIA that will never set a flag of its own.
      QUIET = 1 << 40

      # How many cycles the VIA can run with nothing but its counters
      # changing: no flag set, no pulse on a control line and no bit
      # shifted. See Drive1541::Idle.
      def quiet_cycles
        return 0 if @sr_uses_t2 || @shift_register.clocking? || @ca.pulsing? || @cb.pulsing?

        [@t1.quiet_cycles, @t2.quiet_cycles].min
      end

      # Runs +cycles+ cycles at once, as many as quiet_cycles allows, which
      # moves only the counters.
      def fast_forward(cycles)
        return if cycles.zero?

        @t1.fast_forward(cycles)
        @t2.fast_forward(cycles)
      end

      # Everything the VIA holds but its counters, for comparing it at two
      # points. Timer 1's PB7 level counts only while ACR bit 7 puts it on
      # the pin: nothing reads it otherwise.
      def idle_state
        [@ora, @orb, @ddra, @ddrb, @latch_a, @latch_b, @acr, @pcr, @pb6_high, @ifr.flags, @ifr.enable,
         @acr.anybits?(0x80) && @t1.pb7, *@t1.state, *@t2.state, *@ca.state, *@cb.state, *@shift_register.state]
      end
    end
  end
end
