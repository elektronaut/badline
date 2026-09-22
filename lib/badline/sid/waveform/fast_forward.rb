# frozen_string_literal: true

module Badline
  class SID
    class Waveform
      # Running an oscillator many cycles in one step, for the catch-ups that
      # fast-forward the voices between whole cycles.
      module FastForward
        # Runs `cycles` cycles as #cycle! would, for an oscillator that is not
        # feeding back. What those cycles latch onto the output is left to the
        # whole cycle that follows, which latches over it.
        def fast_forward(cycles)
          drain_floating(cycles) if @selected.zero?
          if @test
            bleed_shift_register(cycles)
          else
            previous = @accumulator
            @accumulator += @frequency * cycles
            # Bit 19 rises at most once a cycle, on each odd multiple of 2^19.
            (((@accumulator + 0x80000) >> 20) - ((previous + 0x80000) >> 20)).times { shift_noise }
            @accumulator &= 0xffffff
          end
          @stale = true
        end

        # The cycle on which the accumulator MSB next rises, counting the next
        # one as 1, or nil if it never will. The test bit leaves the last
        # rise standing for as long as it is held.
        def cycles_to_msb_rise
          return (@msb_rising ? 1 : nil) if @test
          return if @frequency.zero?

          distance = (MSB - @accumulator) & 0xffffff
          distance = 0x1000000 if distance.zero?
          (distance + @frequency - 1) / @frequency
        end

        # A combined waveform writes back into the oscillator every cycle, so
        # it cannot be fast-forwarded.
        def feedback? = !@test && combined?(@selected)

        private

        def drain_floating(cycles)
          return unless @floating_ttl.positive?

          @floating_ttl -= cycles
          return if @floating_ttl.positive?

          @floating_ttl = 0
          @floating = 0x000
        end

        def bleed_shift_register(cycles = 1)
          return unless @shift_register_reset.positive?

          @shift_register_reset -= cycles
          return if @shift_register_reset.positive?

          @shift_register_reset = 0
          @shift_register = SHIFT_REGISTER_RESET
        end
      end
    end
  end
end
