# frozen_string_literal: true

module Badline
  module Chips
    class TED
      class Sound
        # The sound's level averaged over each sample of the audio rate,
        # which integrates the SND pin as the board's RC network does, then
        # through the network's coupling capacitor, a one-pole high-pass at
        # 2.7 Hz run at the audio rate.
        #
        # The corner comes from the Plus/4 schematic (310164, sheet 2): SND
        # reaches the video connector through R10 (1K) and C18 (10 uF) into
        # R11 (12K) and R12 (10K) beside Q3's emitter follower. The
        # network's low-pass, C19 (2,700 pF) at about 70 kHz, is far above
        # any audio rate.
        class Output
          HIGH_PASS_HZ = 2.7

          # Scales the loudest level, both voices high at volume 8, to the
          # top of a signed 16-bit sample.
          SCALE = 32_767.0 / 19_976

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
            @drift = level.to_f
            @high_pass = 1.0 - Math.exp(-2.0 * Math::PI * HIGH_PASS_HZ / rate)
            @samples = []
          end

          # Adds `cycles` cycles at `level`, closing every sample they finish.
          def hold_level(level, cycles)
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
            average = @sum.fdiv(@window)
            @drift += @high_pass * (average - @drift)
            sample = ((average - @drift) * SCALE).round
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
end
