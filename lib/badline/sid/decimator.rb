# frozen_string_literal: true

module Badline
  class SID
    # Reduces the SID's one-sample-per-cycle stream to an audio rate by
    # averaging each window. Point sampling would be cheaper, but the pulse
    # and noise waveforms carry enough energy above the output Nyquist to
    # alias audibly.
    #
    # A sample can stand for several cycles at once, when the DSP has run
    # them as one step.
    class Decimator
      def initialize(clock_hz:, rate:)
        @clock_hz = clock_hz
        @rate = rate
        @phase = 0
        @sum = 0
        @count = 0
        @cycles_to_close = window_cycles
      end

      # Cycles until the current window closes, counting the next one as 1.
      attr_reader :cycles_to_close

      # Returns the averaged sample when these cycles close a window, and
      # nil otherwise. They must not run past the window's end.
      def push(sample, cycles = 1)
        @sum += sample * cycles
        @count += cycles
        @phase += @rate * cycles
        @cycles_to_close -= cycles
        return unless @phase >= @clock_hz

        @phase -= @clock_hz
        @cycles_to_close = window_cycles
        average
      end

      private

      def window_cycles = (@clock_hz - @phase + @rate - 1) / @rate

      def average
        value = @sum.fdiv(@count).round
        @sum = 0
        @count = 0
        value
      end
    end
  end
end
