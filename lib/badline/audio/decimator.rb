# frozen_string_literal: true

module Badline
  module Audio
    # Reduces the SID's one-sample-per-cycle stream to the output rate by
    # averaging each window. Point sampling would be cheaper, but the pulse
    # and noise waveforms carry enough energy above the output Nyquist to
    # alias audibly.
    class Decimator
      def initialize(clock_hz:, rate:)
        @clock_hz = clock_hz
        @rate = rate
        @phase = 0
        @sum = 0
        @count = 0
      end

      # Returns the averaged sample when this cycle closes a window, and nil
      # on every other cycle.
      def push(sample)
        @sum += sample
        @count += 1
        @phase += @rate
        return unless @phase >= @clock_hz

        @phase -= @clock_hz
        average
      end

      private

      def average
        value = @sum.fdiv(@count).round
        @sum = 0
        @count = 0
        value
      end
    end
  end
end
