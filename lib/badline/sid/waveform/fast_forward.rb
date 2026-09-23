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
            while @shift_pipeline.positive? && cycles.positive?
              advance
              cycles -= 1
            end
            skip_ahead(cycles) if cycles.positive?
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

        # Advances an accumulator with no shift in flight. Each rise of bit 19
        # shifts the LFSR two cycles on, so a rise in the last two cycles
        # leaves its shift pending for the cycles after.
        def skip_ahead(cycles)
          previous = @accumulator
          @accumulator += @frequency * cycles
          rises = bit19_rises(previous, @accumulator)
          if rises.positive?
            @shift_pipeline = pipeline_after(cycles)
            rises -= 1 if @shift_pipeline.positive?
            rises.times { shift_noise }
          end
          @accumulator &= 0xffffff
        end

        # Bit 19 rises at most once a cycle, on each odd multiple of 2^19,
        # and at most once in any eight.
        def bit19_rises(from, to) = ((to + 0x80000) >> 20) - ((from + 0x80000) >> 20)

        # How far a rise on one of the last two cycles has come.
        def pipeline_after(cycles)
          last = @accumulator - @frequency
          return 2 if bit19_rises(last, @accumulator).positive?
          return 1 if cycles > 1 && bit19_rises(last - @frequency, last).positive?

          0
        end

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
