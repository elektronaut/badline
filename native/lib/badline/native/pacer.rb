# frozen_string_literal: true

module Badline
  module Native
    # Decides how many cycles each frame clocks and how long it waits.
    #
    # With vsync, a frame lasts one display refresh (see FrameRate), and
    # presenting it waits for the display, so #wait has nothing left to do.
    # While the sound plays, each frame's cycles are trimmed to keep the
    # audio queue at Sound::AHEAD. If presenting doesn't wait, as when the
    # display's driver has vsync off, #check falls back to the timer, and
    # until then the sound holds any frame that would take its queue past
    # SAFETY, so no samples are dropped. #measure fits the frames to the
    # rate the display presents at, measured over the whole run.
    #
    # Without vsync, a frame is one of the machine's frames, 20 ms on PAL.
    # With the sound playing, #wait lasts until the audio queue is down to
    # Sound::AHEAD; otherwise it waits out the rest of the frame.
    class Pacer
      # The frame after which the app first checks that vsync holds.
      EARLY_CHECK = 10
      SAFETY = Sound::AHEAD * 2

      attr_reader :rate

      def initialize(paced:, vsync:, verbose:, region: Region::PAL)
        @paced = paced
        @verbose = verbose
        @vsync = paced && vsync
        @region = region
        @rate = FrameRate.machine(region)
        @deadline = 0.0
        @measured_frames = 0
        @measured_seconds = 0.0
      end

      def vsync? = @vsync

      # Fits the frames to the display's refresh rate, once the window has
      # been opened with vsync.
      def fit(refresh)
        @rate = FrameRate.display(refresh, @region.clock_hz)
        puts "Display #{@rate.refresh} Hz, vsync: #{@rate.base_cycles} cycles a frame" if @verbose
      end

      def start(at)
        @deadline = at
      end

      def cycles(sound)
        return @rate.base_cycles unless @vsync && sound.playing?

        @rate.cycles(sound.level, Sound::AHEAD)
      end

      def wait(sound)
        return unless @paced

        if sound.playing?
          sound.wait(@vsync ? SAFETY : Sound::AHEAD)
        elsif !@vsync
          wait_for_timer
        end
      end

      # Adds `frames` presented over `elapsed` seconds to the measure of the
      # display's rate, and fits the frames to the rate measured so far.
      def measure(frames, elapsed)
        return unless @vsync

        @measured_frames += frames
        @measured_seconds += elapsed
        @rate.refit(@measured_frames, @measured_seconds)
      end

      # Falls back to the timer if the last `frames`, presented over
      # `elapsed` seconds up to `at`, didn't wait for the display.
      def check(frames, elapsed, at)
        return if !@vsync || @rate.vsync_holds?(frames, elapsed)

        puts "Vsync doesn't hold the display's #{@rate.refresh} Hz, so a timer paces the frames instead." if @verbose
        @vsync = false
        @deadline = at
      end

      private

      def wait_for_timer
        @deadline += @rate.seconds
        started = now
        @deadline = started if @deadline < started - @rate.seconds
        left = @deadline - started
        SDL.SDL_Delay((left * 1000).to_i) if left > 0.001
        nil while now < @deadline
      end

      def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
