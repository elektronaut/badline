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

      BUTTONS = {
        up: [SDL::CONTROLLER_BUTTON_DPAD_UP],
        down: [SDL::CONTROLLER_BUTTON_DPAD_DOWN],
        left: [SDL::CONTROLLER_BUTTON_DPAD_LEFT],
        right: [SDL::CONTROLLER_BUTTON_DPAD_RIGHT],
        fire: [SDL::CONTROLLER_BUTTON_A, SDL::CONTROLLER_BUTTON_B,
               SDL::CONTROLLER_BUTTON_X, SDL::CONTROLLER_BUTTON_Y,
               SDL::CONTROLLER_BUTTON_LEFTSHOULDER, SDL::CONTROLLER_BUTTON_RIGHTSHOULDER]
      }.freeze

      AXES = {
        up: [SDL::CONTROLLER_AXIS_LEFTY, -1],
        down: [SDL::CONTROLLER_AXIS_LEFTY, 1],
        left: [SDL::CONTROLLER_AXIS_LEFTX, -1],
        right: [SDL::CONTROLLER_AXIS_LEFTX, 1]
      }.freeze

      def initialize(computer)
        SDL.check(SDL::InitSubSystem.call(SDL::INIT_GAMECONTROLLER))
        @computer = computer
        @controllers = []
        @pressed = Array.new(PORTS.size) { [] }
        rescan
      end

      def names = @controllers.map { |controller| SDL::GameControllerName.call(controller) }

      def rescan
        close
        @controllers = (0...SDL::NumJoysticks.call)
                       .select { |index| SDL::IsGameController.call(index) == 1 }
                       .first(PORTS.size)
                       .map { |index| SDL::GameControllerOpen.call(index) }
                       .reject(&:null?)
      end

      def poll
        @controllers.each_with_index { |controller, index| apply(controller, index) }
      end

      def close
        @controllers.each { |controller| SDL::GameControllerClose.call(controller) }
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
        BUTTONS.fetch(direction).any? { |button| SDL::GameControllerGetButton.call(controller, button) == 1 } ||
          tilted?(controller, direction)
      end

      def tilted?(controller, direction)
        axis, sign = AXES[direction]
        return false unless axis

        SDL::GameControllerGetAxis.call(controller, axis) * sign > DEADZONE
      end

      def joystick(index)
        PORTS[index] == 1 ? @computer.joystick1 : @computer.joystick2
      end
    end
  end
end
