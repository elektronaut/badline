# frozen_string_literal: true

module Badline
  module Native
    # How many cycles a frame clocks and how long it lasts. Without vsync a
    # frame is a PAL frame, 312 lines of 63 cycles over 20 ms. With vsync a
    # frame lasts one display refresh and clocks as many cycles as the
    # machine runs in that time, as badline-ruby does, so a 60 Hz display
    # shows 60 frames of 16,420 cycles a second.
    #
    # A display's reported refresh rate is a whole number, and can be some
    # way off the rate it presents at. #refit sizes the frames to the rate
    # measured instead, as long as that is within REFIT of the reported one.
    #
    # While the sound plays under vsync, the display paces the frames but
    # the audio device consumes the samples, and the two clocks still drift
    # apart. #cycles steers the audio queue towards its target: it trims
    # each frame by up to PROPORTIONAL of the queue's error, and by a trim
    # that builds up by INTEGRAL a frame while the error lasts, up to
    # MAX_TRIM, so the queue settles at the target instead of beside it.
    class FrameRate
      PAL_CLOCK_HZ = 985_248
      PAL_FRAME_CYCLES = 312 * 63
      PAL_FRAME_SECONDS = 0.02
      # A display that reports no refresh rate is taken to run at this.
      DEFAULT_REFRESH = 60
      PROPORTIONAL = 0.02
      INTEGRAL = 0.0001
      MAX_TRIM = 0.05
      # Presenting faster than this many times the refresh rate means vsync
      # isn't waiting for the display.
      VSYNC_SLACK = 1.5
      REFIT = 0.1

      attr_reader :base_cycles, :seconds, :refresh, :trim

      def self.pal = new(PAL_FRAME_CYCLES, PAL_FRAME_SECONDS, 0)

      def self.display(refresh)
        refresh = DEFAULT_REFRESH unless refresh.positive?
        cycles = PAL_CLOCK_HZ / refresh
        new(cycles, cycles.to_f / PAL_CLOCK_HZ, refresh)
      end

      def initialize(base_cycles, seconds, refresh)
        @base_cycles = base_cycles
        @seconds = seconds
        @refresh = refresh
        @trim = 0.0
      end

      # The cycles for the next frame, steering the audio queue's `level`
      # towards `target` (both in seconds).
      def cycles(level, target)
        error = (target - level) / target
        error = 1.0 if error > 1.0
        error = -1.0 if error < -1.0
        @trim += INTEGRAL * error
        @trim = MAX_TRIM if @trim > MAX_TRIM
        @trim = -MAX_TRIM if @trim < -MAX_TRIM
        (@base_cycles * (1.0 + @trim + (PROPORTIONAL * error))).round
      end

      # Sizes the frames to `frames` that lasted `elapsed` seconds.
      def refit(frames, elapsed)
        return unless frames.positive? && elapsed.positive?
        return if ((frames / elapsed) - @refresh).abs > @refresh * REFIT

        @base_cycles = (PAL_CLOCK_HZ * elapsed / frames).round
        @seconds = @base_cycles.to_f / PAL_CLOCK_HZ
      end

      # Whether `frames` presented in `elapsed` seconds kept to the display.
      def vsync_holds?(frames, elapsed)
        return true unless elapsed.positive?

        frames / elapsed <= @refresh * VSYNC_SLACK
      end
    end
  end
end
