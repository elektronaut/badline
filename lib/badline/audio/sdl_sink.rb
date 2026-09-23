# frozen_string_literal: true

module Badline
  module Audio
    # The host's audio device, fed through SDL's queue: mono signed 16-bit
    # samples go in at the device's rate and SDL plays them out behind us.
    #
    # ruby-sdl2 only wraps SDL_mixer, which can't stream raw samples, so the
    # queue API is called through Fiddle on the libSDL2 the extension has
    # already loaded.
    class SDLSink
      class Error < StandardError; end

      INIT_AUDIO = 0x10

      AUDIO_S16SYS = [1].pack("s").getbyte(0) == 1 ? 0x8010 : 0x9010

      ALLOW_FREQUENCY_CHANGE = 0x01

      # int freq; Uint16 format; Uint8 channels, silence; Uint16 samples,
      # padding; Uint32 size; then the callback and userdata pointers.
      SPEC_LAYOUT = "lSCCSSLQQ"

      FUNCTIONS = {
        SDL_InitSubSystem: [%i[uint32], :int],
        SDL_QuitSubSystem: [%i[uint32], :void],
        SDL_GetError: [[], :string],
        SDL_OpenAudioDevice: [%i[pointer int pointer pointer int], :uint32],
        SDL_CloseAudioDevice: [%i[uint32], :void],
        SDL_PauseAudioDevice: [%i[uint32 int], :void],
        SDL_QueueAudio: [%i[uint32 pointer uint32], :int],
        SDL_GetQueuedAudioSize: [%i[uint32], :uint32],
        SDL_ClearQueuedAudio: [%i[uint32], :void]
      }.freeze

      attr_reader :rate

      # With `exact_rate` false SDL may pick the device's own rate instead,
      # which #rate then reports.
      def initialize(rate:, exact_rate: false, buffer: 1024)
        load_sdl
        check(sdl(:SDL_InitSubSystem, INIT_AUDIO))
        @device = open_device(rate, exact_rate ? 0 : ALLOW_FREQUENCY_CHANGE, buffer)
      end

      def queue(samples)
        data = samples.pack("s*")
        check(sdl(:SDL_QueueAudio, @device, data, data.bytesize))
      end

      def queued_seconds = sdl(:SDL_GetQueuedAudioSize, @device).fdiv(2 * rate)

      def start = sdl(:SDL_PauseAudioDevice, @device, 0)

      def pause = sdl(:SDL_PauseAudioDevice, @device, 1)

      def clear = sdl(:SDL_ClearQueuedAudio, @device)

      def close
        return unless @device

        sdl(:SDL_CloseAudioDevice, @device)
        sdl(:SDL_QuitSubSystem, INIT_AUDIO)
        @device = nil
      end

      private

      def open_device(rate, allowed_changes, buffer)
        wanted = [rate, AUDIO_S16SYS, 1, 0, buffer, 0, 0, 0, 0].pack(SPEC_LAYOUT)
        obtained = "\0".b * 32
        device = sdl(:SDL_OpenAudioDevice, nil, 0, wanted, obtained, allowed_changes)
        raise Error, sdl(:SDL_GetError) if device.zero?

        @rate = obtained.unpack1("l")
        device
      end

      def check(result)
        raise Error, sdl(:SDL_GetError) if result.negative?

        result
      end

      def sdl(name, *) = @functions.fetch(name).call(*)

      def load_sdl
        require "fiddle"
        require "sdl2"
        @functions = FUNCTIONS.to_h do |name, (arguments, result)|
          [name, Fiddle::Function.new(Fiddle::Handle::DEFAULT[name.to_s],
                                      arguments.map { |type| fiddle_type(type) }, fiddle_type(result))]
        end
      end

      def fiddle_type(type)
        { uint32: Fiddle::TYPE_UINT32_T, int: Fiddle::TYPE_INT, void: Fiddle::TYPE_VOID,
          pointer: Fiddle::TYPE_VOIDP, string: Fiddle::TYPE_CONST_STRING }.fetch(type)
      end
    end
  end
end
