# frozen_string_literal: true

module Badline
  module Frontend
    # How many cycles a frame clocks and how long it lasts. Without vsync a
    # frame is one of the machine's frames: on PAL 312 lines of 63 cycles
    # over 19.95 ms. With vsync a frame lasts one display refresh and clocks as
    # many cycles as the machine runs in that time, so a 60 Hz display
    # shows 60 PAL frames of 16,420 cycles a second.
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

      # One frame of the machine's raster, from its Timing.
      def self.machine(timing)
        cycles = timing.cycles_per_line * timing.lines_per_frame
        new(cycles, cycles.to_f / timing.clock_hz, 0, timing.clock_hz)
      end

      def self.display(refresh, clock_hz)
        refresh = DEFAULT_REFRESH unless refresh.positive?
        cycles = clock_hz / refresh
        new(cycles, cycles.to_f / clock_hz, refresh, clock_hz)
      end

      def initialize(base_cycles, seconds, refresh, clock_hz)
        @base_cycles = base_cycles
        @seconds = seconds
        @refresh = refresh
        @clock_hz = clock_hz
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

        @base_cycles = (@clock_hz * elapsed / frames).round
        @seconds = @base_cycles.to_f / @clock_hz
      end

      # Whether `frames` presented in `elapsed` seconds kept to the display.
      def vsync_holds?(frames, elapsed)
        return true unless elapsed.positive?

        frames / elapsed <= @refresh * VSYNC_SLACK
      end
    end
  end
end
