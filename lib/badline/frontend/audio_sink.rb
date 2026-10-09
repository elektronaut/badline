# frozen_string_literal: true

module Badline
  module Frontend
    # The host's audio device for --headless and the SID player: a stereo
    # AudioDevice, the left and right samples interleaved, that raises on
    # SDL's failures. It answers what Audio::Playback asks of a sink.
    class AudioSink
      class Error < Audio::Playback::DeviceError; end

      # With `exact_rate` false SDL may pick the device's own rate instead,
      # which #rate then reports.
      def initialize(rate:, exact_rate: false, buffer: 1024)
        @device = AudioDevice.new(channels: 2, rate:, samples: buffer)
        @device.open(exact_rate)
        raise Error, SDL.SDL_GetError unless @device.open?
      end

      def rate = @device.rate

      def queue(samples)
        result = @device.queue(samples)
        raise Error, SDL.SDL_GetError if result.negative?

        result
      end

      def queued_seconds = @device.queued_seconds

      def start = @device.start

      def pause = @device.pause

      def clear = @device.clear

      def close = @device.close
    end
  end
end
