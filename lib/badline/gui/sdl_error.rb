# frozen_string_literal: true

module Badline
  module GUI
    # A failed SDL call, with SDL_GetError's reason.
    class SDLError < StandardError
      # A negative result from SDL is an error.
      def self.check(result)
        raise new(SDL.SDL_GetError) if result.negative?

        result
      end

      # So is a null handle.
      def self.check_pointer(pointer)
        raise new(SDL.SDL_GetError) if pointer.nil?

        pointer
      end
    end
  end
end
