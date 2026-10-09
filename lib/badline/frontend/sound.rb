# frozen_string_literal: true

module Badline
  module Frontend
    # The machine's sound source, the C64's SID or the VIC-20's VIC, on
    # SDL's audio queue, as mono signed 16-bit samples. Both take
    # #record(rate:, clock_hz:) and #drain_samples.
    # Once the device plays, it is the clock: #wait holds each frame until
    # the queue is down to `AHEAD`, so the machine runs at the device's pace.
    #
    # The device starts once the queue holds AHEAD. Below real time the
    # queue runs dry, and the device then stops until it holds AHEAD again,
    # so the sound stutters with silent gaps rather than slowing down. A
    # frame that would take the queue past LIMIT is dropped whole, which
    # only happens unpaced.
    #
    # Each frame's samples go to a mono AudioDevice. The chip's cycles are
    # converted at `clock_hz`, the machine's clock, so an NTSC or Drean
    # machine plays at its own pitch.
    class Sound
      RATE = 44_100
      AHEAD = 0.08
      LIMIT = 0.25

      attr_reader :underruns, :dropped, :queued, :low, :high

      def initialize(source, clock_hz, wanted, verbose)
        @source = source
        @clock_hz = clock_hz
        @verbose = verbose
        @device = AudioDevice.new(channels: 1, rate: RATE, samples: 512)
        @started = false
        @muted = false
        @underruns = 0
        @dropped = 0
        @queued = 0
        reset_levels
        open_device if wanted
      end

      def rate = @device.rate

      def on? = @device.open?

      # Plays another machine's sound from here on, at that machine's clock.
      def switch(source, clock_hz)
        @source = source
        @clock_hz = clock_hz
        record if on?
      end

      def muted? = @muted

      def playing? = @started

      def feed
        return unless on?

        samples = @source.drain_samples
        return if @muted || samples.empty?

        level = queued_seconds
        if level + (samples.size.to_f / rate) > LIMIT
          @dropped += samples.size
        else
          play(samples, level)
        end
      end

      # How much the audio queue holds, in seconds.
      def level = queued_seconds

      # Waits until the queue is down to `level` seconds.
      def wait(level = AHEAD)
        SDL.SDL_Delay(1) while queued_seconds > level
      end

      def toggle_mute
        @muted = !@muted
        return unless @muted

        halt
        @device.clear
      end

      def reset_levels
        @low = LIMIT
        @high = 0.0
      end

      def close
        @device.close
      end

      private

      def open_device
        @device.open(false)
        return puts "No sound: #{SDL.SDL_GetError}" unless on?

        record
        puts "Sound at #{rate} Hz" if @verbose
      end

      def record = @source.record(rate: @device.rate, clock_hz: @clock_hz)

      def queued_seconds = @device.queued_seconds

      def play(samples, level)
        @low = level if level < @low
        underrun! if @started && level.zero?
        queue(samples)
        level = queued_seconds
        @high = level if level > @high
        start if level >= AHEAD
      end

      def queue(samples)
        @device.queue(samples)
        @queued += samples.size
      end

      def start
        return if @started

        @started = true
        @device.start
      end

      def halt
        @started = false
        @device.pause
      end

      def underrun!
        @underruns += 1
        halt
      end
    end
  end
end
