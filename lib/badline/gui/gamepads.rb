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
    # instance id, and the binding gives no way to line the two up, so this
    # class polls the controllers every frame. It only releases directions it
    # pressed itself, so the keyboard mapping keeps working with a pad
    # connected.
    class Gamepads
      DEADZONE = 8_000
      PORTS = [2, 1].freeze

      BUTTONS = {
        up: [SDL2::GameController::Button::DPAD_UP],
        down: [SDL2::GameController::Button::DPAD_DOWN],
        left: [SDL2::GameController::Button::DPAD_LEFT],
        right: [SDL2::GameController::Button::DPAD_RIGHT],
        fire: [SDL2::GameController::Button::A, SDL2::GameController::Button::B,
               SDL2::GameController::Button::X, SDL2::GameController::Button::Y,
               SDL2::GameController::Button::LEFTSHOULDER,
               SDL2::GameController::Button::RIGHTSHOULDER]
      }.freeze

      AXES = {
        up: [SDL2::GameController::Axis::LEFTY, -1],
        down: [SDL2::GameController::Axis::LEFTY, 1],
        left: [SDL2::GameController::Axis::LEFTX, -1],
        right: [SDL2::GameController::Axis::LEFTX, 1]
      }.freeze

      def initialize(computer)
        SDL2.init(SDL2::INIT_GAMECONTROLLER)
        @computer = computer
        @controllers = []
        @pressed = Array.new(PORTS.size) { [] }
        rescan
      end

      def names = @controllers.map(&:name)

      def rescan
        close
        @controllers = (0...SDL2::Joystick.num_connected_joysticks)
                       .select { |index| SDL2::Joystick.game_controller?(index) }
                       .first(PORTS.size)
                       .map { |index| SDL2::GameController.open(index) }
      end

      def poll
        @controllers.each_with_index { |controller, index| apply(controller, index) }
      end

      def close
        @controllers.each { |controller| controller.destroy unless controller.destroy? }
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
        BUTTONS.fetch(direction).any? { |button| controller.button_pressed?(button) } ||
          tilted?(controller, direction)
      end

      def tilted?(controller, direction)
        axis, sign = AXES[direction]
        return false unless axis

        controller.axis(axis) * sign > DEADZONE
      end

      def joystick(index)
        PORTS[index] == 1 ? @computer.joystick1 : @computer.joystick2
      end
    end
  end
end
