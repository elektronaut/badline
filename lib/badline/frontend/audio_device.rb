# frozen_string_literal: true

module Badline
  module Frontend
    # An SDL audio device on SDL's queue: signed 16-bit samples, `channels`
    # of them interleaved per frame, go in at the device's rate and SDL
    # plays them out behind us. When #open fails the device stays closed,
    # with the reason in SDL_GetError for the caller to report.
    class AudioDevice
      attr_reader :rate

      def initialize(channels:, rate:, samples:)
        @channels = channels
        @rate = rate
        @samples = samples
        @device = 0
        @buffer = IO::Buffer.new(4096)
      end

      def open? = @device != 0

      # With `exact_rate` false SDL may pick the device's own rate instead,
      # which #rate then reports.
      def open(exact_rate)
        return unless SDL.SDL_InitSubSystem(SDL::INIT_AUDIO).zero?

        SDL.spec_freq(SDL.wanted, @rate)
        SDL.spec_format(SDL.wanted, SDL::AUDIO_S16LSB)
        SDL.spec_channels(SDL.wanted, @channels)
        SDL.spec_samples(SDL.wanted, @samples)
        allowed_changes = exact_rate ? 0 : SDL::ALLOW_FREQUENCY_CHANGE
        @device = SDL.SDL_OpenAudioDevice(nil, 0, SDL.wanted, SDL.obtained, allowed_changes)
        @rate = SDL.read_i32(SDL.obtained) if open?
      end

      # Returns SDL_QueueAudio's result, negative on failure.
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
      end

      def queued_seconds = SDL.SDL_GetQueuedAudioSize(@device) / (2.0 * @channels * @rate)

      def start = SDL.SDL_PauseAudioDevice(@device, 0)

      def pause = SDL.SDL_PauseAudioDevice(@device, 1)

      def clear = SDL.SDL_ClearQueuedAudio(@device)

      def close
        return unless open?

        SDL.SDL_CloseAudioDevice(@device)
        SDL.SDL_QuitSubSystem(SDL::INIT_AUDIO)
        @device = 0
      end
    end
  end
end
