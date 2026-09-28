# frozen_string_literal: true

module Badline
  module Native
    # The SID's output on SDL's audio queue, as mono signed 16-bit samples.
    # Once the device plays, it is the clock: #wait holds each frame until
    # the queue is down to `AHEAD`, so the machine runs at the device's pace.
    #
    # The device starts once the queue holds AHEAD. Below real time the
    # queue runs dry, and the device then stops until it holds AHEAD again,
    # so the sound stutters with silent gaps rather than slowing down. A
    # frame that would take the queue past LIMIT is dropped whole, which
    # only happens unpaced.
    #
    # Each frame's samples go to SDL through an IO::Buffer of 16-bit values.
    class Sound
      RATE = 44_100
      AHEAD = 0.08
      LIMIT = 0.25

      attr_reader :rate, :underruns, :dropped, :queued, :low, :high

      def initialize(sid, wanted, verbose)
        @sid = sid
        @verbose = verbose
        @device = 0
        @rate = RATE
        @started = false
        @muted = false
        @underruns = 0
        @dropped = 0
        @queued = 0
        @buffer = IO::Buffer.new(4096)
        reset_levels
        open_device if wanted
      end

      def on? = @device != 0

      def muted? = @muted

      def playing? = @started

      def feed
        return unless on?

        samples = @sid.drain_samples
        return if @muted || samples.empty?

        level = queued_seconds
        if level + (samples.size.to_f / @rate) > LIMIT
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
        SDL.SDL_ClearQueuedAudio(@device)
      end

      def reset_levels
        @low = LIMIT
        @high = 0.0
      end

      def close
        SDL.SDL_CloseAudioDevice(@device) if on?
      end

      private

      def open_device
        unless SDL.SDL_InitSubSystem(SDL::INIT_AUDIO).zero?
          puts "No sound: #{SDL.SDL_GetError}"
          return
        end

        SDL.spec_freq(SDL.wanted, RATE)
        SDL.spec_format(SDL.wanted, SDL::AUDIO_S16LSB)
        SDL.spec_channels(SDL.wanted, 1)
        SDL.spec_samples(SDL.wanted, 512)
        @device = SDL.SDL_OpenAudioDevice(nil, 0, SDL.wanted, SDL.obtained, SDL::ALLOW_FREQUENCY_CHANGE)
        return puts "No sound: #{SDL.SDL_GetError}" unless on?

        @rate = SDL.read_i32(SDL.obtained)
        @sid.record(rate: @rate)
        puts "Sound at #{@rate} Hz" if @verbose
      end

      def queued_seconds = SDL.SDL_GetQueuedAudioSize(@device) / (2.0 * @rate)

      def play(samples, level)
        @low = level if level < @low
        underrun! if @started && level.zero?
        queue(samples)
        level = queued_seconds
        @high = level if level > @high
        start if level >= AHEAD
      end

      def queue(samples)
        count = samples.size
        bytes = count * 2
        @buffer.resize(bytes) if bytes > @buffer.size
        buffer = @buffer
        i = 0
        while i < count
          buffer.set_value(:s16, i * 2, samples[i])
          i += 1
        end
        SDL.SDL_QueueAudio(@device, buffer, bytes)
        @queued += count
      end

      def start
        return if @started

        @started = true
        SDL.SDL_PauseAudioDevice(@device, 0)
      end

      def halt
        @started = false
        SDL.SDL_PauseAudioDevice(@device, 1)
      end

      def underrun!
        @underruns += 1
        puts "Running below real time, so the sound will stutter." if @underruns == 1
        halt
      end
    end
  end
end
