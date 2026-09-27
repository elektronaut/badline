# frozen_string_literal: true

module Badline
  module Audio
    # The host's audio device, fed through SDL's queue: mono signed 16-bit
    # samples go in at the device's rate and SDL plays them out behind us.
    class SDLSink
      class Error < StandardError; end

      # int freq; Uint16 format; Uint8 channels, silence; Uint16 samples,
      # padding; Uint32 size; then the callback and userdata pointers.
      SPEC_LAYOUT = "lSCCSSLQQ"

      attr_reader :rate

      # With `exact_rate` false SDL may pick the device's own rate instead,
      # which #rate then reports.
      def initialize(rate:, exact_rate: false, buffer: 1024)
        load_sdl
        check(SDL::InitSubSystem.call(SDL::INIT_AUDIO))
        @device = open_device(rate, exact_rate ? 0 : SDL::AUDIO_ALLOW_FREQUENCY_CHANGE, buffer)
      end

      def queue(samples)
        data = samples.pack("s*")
        check(SDL::QueueAudio.call(@device, data, data.bytesize))
      end

      def queued_seconds = SDL::GetQueuedAudioSize.call(@device).fdiv(2 * rate)

      def start = SDL::PauseAudioDevice.call(@device, 0)

      def pause = SDL::PauseAudioDevice.call(@device, 1)

      def clear = SDL::ClearQueuedAudio.call(@device)

      def close
        return unless @device

        SDL::CloseAudioDevice.call(@device)
        SDL::QuitSubSystem.call(SDL::INIT_AUDIO)
        @device = nil
      end

      private

      def open_device(rate, allowed_changes, buffer)
        wanted = [rate, SDL::AUDIO_S16SYS, 1, 0, buffer, 0, 0, 0, 0].pack(SPEC_LAYOUT)
        obtained = "\0".b * 32
        device = SDL::OpenAudioDevice.call(nil, 0, wanted, obtained, allowed_changes)
        raise Error, SDL.error if device.zero?

        @rate = obtained.unpack1("l")
        device
      end

      def load_sdl
        require "badline/sdl"
      rescue SDL::Error => e
        raise Error, e.message
      end

      def check(result)
        raise Error, SDL.error if result.negative?

        result
      end
    end
  end
end
