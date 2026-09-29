# frozen_string_literal: true

module Badline
  module Audio
    # The host's audio device, fed through SDL's queue: mono signed 16-bit
    # samples go in at the device's rate and SDL plays them out behind us.
    class SDLSink
      class Error < Playback::DeviceError; end

      attr_reader :rate

      # With `exact_rate` false SDL may pick the device's own rate instead,
      # which #rate then reports.
      def initialize(rate:, exact_rate: false, buffer: 1024)
        load_sdl
        check(SDL.SDL_InitSubSystem(SDL::INIT_AUDIO))
        @device = open_device(rate, exact_rate ? 0 : SDL::ALLOW_FREQUENCY_CHANGE, buffer)
      end

      def queue(samples)
        data = samples.pack("s<*")
        check(SDL.SDL_QueueAudio(@device, data, data.bytesize))
      end

      def queued_seconds = SDL.SDL_GetQueuedAudioSize(@device).fdiv(2 * rate)

      def start = SDL.SDL_PauseAudioDevice(@device, 0)

      def pause = SDL.SDL_PauseAudioDevice(@device, 1)

      def clear = SDL.SDL_ClearQueuedAudio(@device)

      def close
        return unless @device

        SDL.SDL_CloseAudioDevice(@device)
        SDL.SDL_QuitSubSystem(SDL::INIT_AUDIO)
        @device = nil
      end

      private

      def open_device(rate, allowed_changes, buffer)
        SDL.spec_freq(SDL.wanted, rate)
        SDL.spec_format(SDL.wanted, SDL::AUDIO_S16LSB)
        SDL.spec_channels(SDL.wanted, 1)
        SDL.spec_samples(SDL.wanted, buffer)
        device = SDL.SDL_OpenAudioDevice(nil, 0, SDL.wanted, SDL.obtained, allowed_changes)
        raise Error, SDL.SDL_GetError if device.zero?

        @rate = SDL.read_i32(SDL.obtained)
        device
      end

      def load_sdl
        require "badline/ffi"
        require "badline/sdl"
      rescue FFI::Error => e
        raise Error, e.message
      end

      def check(result)
        raise Error, SDL.SDL_GetError if result.negative?

        result
      end
    end
  end
end
