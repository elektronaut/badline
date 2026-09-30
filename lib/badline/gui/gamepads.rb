# frozen_string_literal: true

module Badline
  module GUI
    # Host game controllers wired onto the control ports.
    #
    # The first controller found drives joystick 2, the port most games read;
    # a second one drives joystick 1. D-pad and left stick both steer, every
    # face and shoulder button fires.
    #
    # SDL announces arrivals by device index but reports button presses by
    # instance id, so rather than line the two up, this class polls the
    # controllers every frame. It only releases directions it
    # pressed itself, so the keyboard mapping keeps working with a pad
    # connected.
    class Gamepads
      DEADZONE = 8_000
      PORTS = [2, 1].freeze

      # SDL's controller axes and buttons.
      AXIS_LEFTX = 0
      AXIS_LEFTY = 1
      BUTTON_A = 0
      BUTTON_B = 1
      BUTTON_X = 2
      BUTTON_Y = 3
      BUTTON_LEFTSHOULDER = 9
      BUTTON_RIGHTSHOULDER = 10
      BUTTON_DPAD_UP = 11
      BUTTON_DPAD_DOWN = 12
      BUTTON_DPAD_LEFT = 13
      BUTTON_DPAD_RIGHT = 14

      BUTTONS = {
        up: [BUTTON_DPAD_UP],
        down: [BUTTON_DPAD_DOWN],
        left: [BUTTON_DPAD_LEFT],
        right: [BUTTON_DPAD_RIGHT],
        fire: [BUTTON_A, BUTTON_B, BUTTON_X, BUTTON_Y, BUTTON_LEFTSHOULDER, BUTTON_RIGHTSHOULDER]
      }.freeze

      AXES = {
        up: [AXIS_LEFTY, -1],
        down: [AXIS_LEFTY, 1],
        left: [AXIS_LEFTX, -1],
        right: [AXIS_LEFTX, 1]
      }.freeze

      def initialize(computer)
        SDLError.check(SDL.SDL_InitSubSystem(SDL::INIT_GAMECONTROLLER))
        @computer = computer
        @controllers = []
        @pressed = Array.new(PORTS.size) { [] }
        rescan
      end

      def names = @controllers.map { |controller| SDL.SDL_GameControllerName(controller) }

      def rescan
        close
        @controllers = (0...SDL.SDL_NumJoysticks)
                       .select { |index| SDL.SDL_IsGameController(index) == 1 }
                       .first(PORTS.size)
                       .filter_map { |index| SDL.SDL_GameControllerOpen(index) }
      end

      # Wires the controllers to another machine's joysticks, which take
      # what they hold on the next poll.
      def computer=(computer)
        @computer = computer
        @pressed.map! { [] }
      end

      def poll
        @controllers.each_with_index { |controller, index| apply(controller, index) }
      end

      def close
        @controllers.each { |controller| SDL.SDL_GameControllerClose(controller) }
        @controllers = []
        @pressed.size.times { |index| release(index) }
      end

      private

      def apply(controller, index)
        active = Joystick::DIRECTIONS.keys.select { |dir| active?(controller, dir) }
        (@pressed[index] - active).each { |dir| joystick(index).release(dir) }
        active.each { |dir| joystick(index).press(dir) }
        @pressed[index] = active
      end

      def release(index)
        @pressed[index].each { |dir| joystick(index).release(dir) }
        @pressed[index] = []
      end

      def active?(controller, direction)
        BUTTONS.fetch(direction).any? { |button| SDL.SDL_GameControllerGetButton(controller, button) == 1 } ||
          tilted?(controller, direction)
      end

      def tilted?(controller, direction)
        axis, sign = AXES[direction]
        return false unless axis

        SDL.SDL_GameControllerGetAxis(controller, axis) * sign > DEADZONE
      end

      def joystick(index)
        PORTS[index] == 1 ? @computer.joystick1 : @computer.joystick2
      end
    end
  end
end
