# frozen_string_literal: true

module Badline
  module GUI
    # The SDL events the front end handles, read from SDL.event at the
    # offsets its keyboard, mouse and controller members use.
    module Event
      Quit = Data.define
      # A held key sends repeats.
      KeyDown = Data.define(:sym, :mod, :repeat) do
        def initialize(sym:, mod:, repeat: false) = super
      end
      KeyUp = Data.define(:sym, :mod)
      MouseMotion = Data.define(:xrel, :yrel)
      MouseButton = Data.define(:button, :pressed)
      ControllerDevice = Data.define

      CONTROLLER_DEVICE = [SDL::CONTROLLERDEVICEADDED, SDL::CONTROLLERDEVICEREMOVED,
                           SDL::CONTROLLERDEVICEREMAPPED].freeze

      # The next event the front end handles, skipping the others, or nil
      # once the queue is empty.
      def self.poll
        while SDL.SDL_PollEvent(SDL.event) == 1
          event = decode(SDL.event)
          return event if event
        end
        nil
      end

      def self.decode(event)
        type = SDL.event_type(event)
        case type
        when SDL::QUIT then Quit.new
        when SDL::KEYDOWN then KeyDown.new(SDL.event_sym(event), SDL.event_mod(event), SDL.event_repeat(event) != 0)
        when SDL::KEYUP then KeyUp.new(SDL.event_sym(event), SDL.event_mod(event))
        when SDL::MOUSEMOTION then MouseMotion.new(SDL.event_xrel(event), SDL.event_yrel(event))
        when SDL::MOUSEBUTTONDOWN, SDL::MOUSEBUTTONUP
          MouseButton.new(SDL.event_button(event), type == SDL::MOUSEBUTTONDOWN)
        when *CONTROLLER_DEVICE then ControllerDevice.new
        end
      end

      def self.key_name(sym) = SDL.SDL_GetKeyName(sym)
    end
  end
end
