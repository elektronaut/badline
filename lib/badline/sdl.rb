# frozen_string_literal: true

require "fiddle"

module Badline
  # The libSDL2 calls the window, the gamepads and the audio sink make,
  # bound through Fiddle, so nothing has to compile against SDL at install
  # time. Only the library itself has to be present.
  #
  # Each function is a constant named after its C name without the prefix:
  # SDL::RenderClear.call(renderer) calls SDL_RenderClear. They're built
  # with need_gvl, which skips releasing Ruby's lock around the call: none
  # of these block for long, and releasing it costs more than most of them.
  module SDL
    class Error < StandardError; end

    # Where package managers put the shared library. dlopen searches the
    # system paths for the bare names, but not Homebrew's.
    LIBRARIES = %w[
      libSDL2-2.0.so.0 libSDL2.so
      libSDL2-2.0.0.dylib /opt/homebrew/lib/libSDL2-2.0.0.dylib /usr/local/lib/libSDL2-2.0.0.dylib
      SDL2.dll
    ].freeze

    def self.open_library
      LIBRARIES.each do |name|
        return Fiddle.dlopen(name)
      rescue Fiddle::DLError
        next
      end
      raise Error, "can't find libSDL2 (tried #{LIBRARIES.join(', ')})"
    end

    LIBRARY = open_library

    VOID = Fiddle::TYPE_VOID
    INT = Fiddle::TYPE_INT
    UINT8 = Fiddle::TYPE_UINT8_T
    INT16 = Fiddle::TYPE_INT16_T
    UINT32 = Fiddle::TYPE_UINT32_T
    POINTER = Fiddle::TYPE_VOIDP
    STRING = Fiddle::TYPE_CONST_STRING

    def self.function(name, arguments, result)
      Fiddle::Function.new(LIBRARY[name], arguments, result, name:, need_gvl: true)
    end

    def self.error = GetError.call

    # A negative result from SDL is an error, and SDL_GetError says which.
    def self.check(result)
      raise Error, error if result.negative?

      result
    end

    # So is a null handle.
    def self.check_pointer(pointer)
      raise Error, error if pointer.null?

      pointer
    end
  end
end

require "badline/sdl/functions"
require "badline/sdl/events"
