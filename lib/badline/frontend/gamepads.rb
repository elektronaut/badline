# frozen_string_literal: true

module Badline
  module Frontend
    # Host game controllers wired onto the control ports: the first
    # controller found drives joystick 2, the port most games read, and a
    # second one joystick 1. PadPort holds the mapping.
    #
    # The controllers are polled every frame, and rescanned whenever SDL
    # reports one added or removed.
    class Gamepads
      PORTS = [2, 1].freeze

      def initialize(computer, verbose)
        @verbose = verbose
        @controllers = []
        @ports = [PadPort.new(computer.joystick2), PadPort.new(computer.joystick1)]
        @buttons = Array.new(PadPort::BUTTON_COUNT, 0)
        @available = SDL.SDL_InitSubSystem(SDL::INIT_GAMECONTROLLER).zero?
        puts "No game controllers: #{SDL.SDL_GetError}" if @verbose && !@available
      end

      # Wires the controllers to another machine's joysticks, which take
      # what they hold on the next poll.
      def computer=(computer)
        @ports.each(&:release)
        @ports = [PadPort.new(computer.joystick2), PadPort.new(computer.joystick1)]
      end

      def rescan
        return unless @available

        close
        index = 0
        count = SDL.SDL_NumJoysticks
        while index < count && @controllers.size < PORTS.size
          open_controller(index) if SDL.SDL_IsGameController(index) != 0
          index += 1
        end
      end

      def poll
        @controllers.each_with_index { |controller, index| @ports[index].update(active(controller)) }
      end

      def close
        @controllers.each { |controller| SDL.SDL_GameControllerClose(controller) }
        @controllers = []
        @ports.each(&:release)
      end

      private

      def open_controller(index)
        controller = SDL.SDL_GameControllerOpen(index)
        # SDL returns NULL when the controller won't open, which Spinel's FFI
        # reads as nil.
        return if controller.nil?

        puts "Gamepad on joystick #{PORTS[@controllers.size]}: #{SDL.SDL_GameControllerName(controller)}" if @verbose
        @controllers << controller
      end

      def active(controller)
        buttons = @buttons
        button = 0
        while button < PadPort::BUTTON_COUNT
          buttons[button] = SDL.SDL_GameControllerGetButton(controller, button)
          button += 1
        end
        PadPort.active(buttons, SDL.SDL_GameControllerGetAxis(controller, PadPort::LEFT_X),
                       SDL.SDL_GameControllerGetAxis(controller, PadPort::LEFT_Y))
      end
    end
  end
end
