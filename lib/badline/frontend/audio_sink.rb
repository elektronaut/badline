# frozen_string_literal: true

module Badline
  module Frontend
    # The host's audio device for --headless and the SID player, fed through
    # SDL's queue: stereo signed 16-bit samples, the left and right
    # interleaved, go in at the device's rate and SDL plays them out behind
    # us. It answers what Audio::Playback asks of a sink.
    class AudioSink
      class Error < Audio::Playback::DeviceError; end

      attr_reader :rate

      # With `exact_rate` false SDL may pick the device's own rate instead,
      # which #rate then reports.
      def initialize(rate:, exact_rate: false, buffer: 1024)
        @device = 0
        @rate = rate
        @buffer = IO::Buffer.new(4096)
        check(SDL.SDL_InitSubSystem(SDL::INIT_AUDIO))
        open_device(rate, exact_rate ? 0 : SDL::ALLOW_FREQUENCY_CHANGE, buffer)
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
        check(SDL.SDL_QueueAudio(@device, buffer, bytes))
      end

      def queued_seconds = SDL.SDL_GetQueuedAudioSize(@device) / (4.0 * @rate)

      def start = SDL.SDL_PauseAudioDevice(@device, 0)

      def pause = SDL.SDL_PauseAudioDevice(@device, 1)

      def clear = SDL.SDL_ClearQueuedAudio(@device)

      def close
        return if @device.zero?

        SDL.SDL_CloseAudioDevice(@device)
        SDL.SDL_QuitSubSystem(SDL::INIT_AUDIO)
        @device = 0
      end

      private

      def open_device(rate, allowed_changes, buffer)
        SDL.spec_freq(SDL.wanted, rate)
        SDL.spec_format(SDL.wanted, SDL::AUDIO_S16LSB)
        SDL.spec_channels(SDL.wanted, 2)
        SDL.spec_samples(SDL.wanted, buffer)
        @device = SDL.SDL_OpenAudioDevice(nil, 0, SDL.wanted, SDL.obtained, allowed_changes)
        raise Error, SDL.SDL_GetError if @device.zero?

        @rate = SDL.read_i32(SDL.obtained)
      end

      def check(result)
        raise Error, SDL.SDL_GetError if result.negative?

        result
      end
    end
  end
end
