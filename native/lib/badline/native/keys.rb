# frozen_string_literal: true

module Badline
  module Native
    # SDL scancodes follow key positions on a US layout. They map onto the C64
    # keys GUI::KeyMap and GUI::JoyMap give the same keys by name.
    module Keys
      TAB = 43

      LETTERS = %i[a b c d e f g h i j k l m n o p q r s t u v w x y z].freeze
      DIGITS = %i[1 2 3 4 5 6 7 8 9 0].freeze

      OTHERS = {
        40 => :return, 41 => :run_stop, 42 => :delete, 44 => :space,
        45 => :-, 46 => :"=", 49 => :"@", 51 => :";", 52 => :":",
        48 => :up, 53 => :left, 54 => :",", 55 => :".", 56 => :/,
        58 => :f1, 60 => :f3, 62 => :f5, 64 => :f7,
        74 => :clr_home, 75 => :restore, 77 => :£, 79 => :cursor_h, 80 => :cursor_left,
        81 => :cursor_v, 82 => :cursor_up, 85 => :*, 87 => :+,
        224 => :control, 225 => :lshift, 226 => :cbm, 229 => :rshift
      }.freeze

      F9 = 66
      F10 = 67
      F11 = 68
      F12 = 69

      ARROWS = { 44 => :fire, 228 => :fire, 79 => :right, 80 => :left, 81 => :down, 82 => :up }.freeze
      WASD = { 225 => :fire, 7 => :right, 4 => :left, 22 => :down, 26 => :up }.freeze

      def self.c64_key(scancode)
        if scancode.between?(4, 29)
          LETTERS[scancode - 4]
        elsif scancode.between?(30, 39)
          DIGITS[scancode - 30]
        else
          OTHERS[scancode] || :none
        end
      end

      def self.arrows(scancode) = ARROWS[scancode] || :none

      def self.wasd(scancode) = WASD[scancode] || :none

      def self.joystick?(scancode) = ARROWS.key?(scancode) || WASD.key?(scancode)
    end
  end
end
