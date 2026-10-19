# frozen_string_literal: true

module Badline
  module Machine
    # The sound of one logic line a machine drives into its speaker or
    # audio output, such as the PET's CB2 or the KIM-1's PB7. The class
    # that includes it answers #line_high?, the line's level this cycle.
    #
    # The machine calls #cycle! once a cycle while #recording?, from #record
    # on, so a sound nobody records costs only that check. Each sample is
    # the share of its cycles the line spent high, through the output
    # stage: a one-pole low-pass at 5 kHz and a one-pole high-pass at
    # 100 Hz, so a line left high or low settles to silence.
    module LineSound
      LOW_PASS_HZ = 5_000
      HIGH_PASS_HZ = 100

      # A swing from the line low to the line high, as a signed 16-bit
      # sample.
      SCALE = 24_000.0

      attr_reader :recording
      alias recording? recording

      # Starts collecting the output, averaged down to `rate` samples a
      # second at `clock_hz` cycles a second, for #drain_samples. The
      # output stage takes the line's level now as settled.
      def record(rate:, clock_hz: 1_000_000)
        @rate = rate
        @clock_hz = clock_hz
        @remainder = 0
        @window = next_window
        @left = @window
        @sum = 0
        @high = line_high?
        @run = 0
        @low = @drift = @high ? 1.0 : 0.0
        @low_pass = 1.0 - Math.exp(-2.0 * Math::PI * LOW_PASS_HZ / rate)
        @high_pass = 1.0 - Math.exp(-2.0 * Math::PI * HIGH_PASS_HZ / rate)
        @samples = []
        @recording = true
      end

      # Takes the line's level for this cycle, while recording.
      def cycle!
        high = line_high?
        if high == @high
          @run += 1
        else
          hold(@high, @run)
          @high = high
          @run = 1
        end
      end

      # The samples closed since the last drain.
      def drain_samples
        return [] unless @recording

        hold(@high, @run)
        @run = 0
        samples = @samples
        @samples = []
        samples
      end

      private

      def init_line_sound
        @recording = false
        @high = true
        @run = 0
        @rate = 0
        @clock_hz = 0
        @remainder = 0
        @window = 0
        @left = 0
        @sum = 0
        @low = 0.0
        @drift = 0.0
        @low_pass = 0.0
        @high_pass = 0.0
        @samples = []
      end

      # Adds `cycles` cycles with the line high or low, closing every
      # sample they finish.
      def hold(high, cycles)
        left = @left
        while cycles >= left
          @sum += left if high
          cycles -= left
          close
          left = @left
        end
        @sum += cycles if high
        @left = left - cycles
      end

      def close
        @low += @low_pass * (@sum.fdiv(@window) - @low)
        @drift += @high_pass * (@low - @drift)
        sample = ((@low - @drift) * SCALE).round
        sample = 32_767 if sample > 32_767
        sample = -32_768 if sample < -32_768
        @samples << sample
        @sum = 0
        @window = next_window
        @left = @window
      end

      # Each window is a whole number of cycles, and they add up to the
      # clock's cycles over a second.
      def next_window
        @remainder += @clock_hz
        cycles = @remainder / @rate
        @remainder -= cycles * @rate
        cycles
      end
    end
  end
end
