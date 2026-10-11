# frozen_string_literal: true

module Badline
  class Vic20
    class Sound
      # The sound's level averaged over each sample of the audio rate, then
      # through the machine's output stage: a one-pole low-pass at 1,420 Hz
      # and a one-pole high-pass at 158 Hz, both run at the audio rate.
      #
      # The two corners are fitted to xvic's step response: a voice turned
      # on at volume 15 rises and decays back to the line as those two RC
      # stages do, within 6 parts in 11,000.
      class Output
        LOW_PASS_HZ = 1_420
        HIGH_PASS_HZ = 158

        # Scales the loudest level, four voices high at volume 15, to the
        # top of a signed 16-bit sample.
        SCALE = 32_767.0 / 570

        attr_reader :samples

        # `level` is the sound's level as the recording starts, which the
        # stage takes as settled.
        def initialize(clock_hz:, rate:, level:)
          @clock_hz = clock_hz
          @rate = rate
          @remainder = 0
          @window = next_window
          @left = @window
          @sum = 0
          @low = @drift = level.to_f
          @low_pass = 1.0 - Math.exp(-2.0 * Math::PI * LOW_PASS_HZ / rate)
          @high_pass = 1.0 - Math.exp(-2.0 * Math::PI * HIGH_PASS_HZ / rate)
          @samples = []
        end

        # Adds `cycles` cycles at `level`, closing every sample they finish.
        def hold(level, cycles)
          left = @left
          while cycles >= left
            @sum += level * left
            cycles -= left
            close
            left = @left
          end
          @sum += level * cycles
          @left = left - cycles
        end

        # The samples closed since the last drain.
        def drain
          samples = @samples
          @samples = []
          samples
        end

        private

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
end
