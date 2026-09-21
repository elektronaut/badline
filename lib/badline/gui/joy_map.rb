# frozen_string_literal: true

module Badline
  module GUI
    # Maps host keys onto the two control ports while joystick mode is on.
    #
    # The arrow cluster plus space drives joystick 2, WASD plus left shift
    # joystick 1, so both ports can be played at once.
    class JoyMap
      PORTS = {
        2 => { "Up" => :up, "Down" => :down, "Left" => :left, "Right" => :right, "Space" => :fire }.freeze,
        1 => { "W" => :up, "S" => :down, "A" => :left, "D" => :right, "Left Shift" => :fire }.freeze
      }.freeze

      def self.parse(event)
        name = SDL2::Key.name_of(event.sym)

        PORTS.each do |port, map|
          direction = map[name]
          return [port, direction] if direction
        end

        nil
      end
    end
  end
end
