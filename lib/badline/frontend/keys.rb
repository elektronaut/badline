# frozen_string_literal: true

module Badline
  module Frontend
    # SDL scancodes follow key positions on a US layout. They map onto the C64
    # keys, the C128's own keys and, in joystick mode, the joystick
    # directions.
    module Keys
      RETURN = 40
      ESCAPE = 41
      BACKSPACE = 42
      TAB = 43
      SPACE = 44
      F8 = 65
      F9 = 66
      F10 = 67
      F11 = 68
      F12 = 69
      HOME = 74
      PAGE_UP = 75
      END_KEY = 77
      PAGE_DOWN = 78
      RIGHT = 79
      LEFT = 80
      DOWN = 81
      UP = 82

      # The arrow keys, which move through the menus.
      DIRECTIONS = { RIGHT => :right, LEFT => :left, DOWN => :down, UP => :up }.freeze

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

      # The C128's keys that have a host key of their own: the keypad, HELP
      # on Insert or Help, ALT on the right Alt, NO SCROLL on Scroll Lock,
      # and CAPS LOCK and 40/80 DISPLAY, which sit outside the matrix, on
      # Caps Lock and F6 or Pause. In C128 mode Esc is ESC, and RUN/STOP
      # moves to Page Down. TAB and the separate cursor keys stay with the
      # C64's keys (the joystick toggle and the cursor combinations), and in
      # C64 mode Esc stays RUN/STOP.
      C128_OTHERS = {
        89 => :keypad1, 90 => :keypad2, 91 => :keypad3, 92 => :keypad4, 93 => :keypad5, 94 => :keypad6,
        95 => :keypad7, 96 => :keypad8, 97 => :keypad9, 98 => :keypad0, 99 => :keypad_period,
        86 => :keypad_minus, 87 => :keypad_plus, 88 => :keypad_enter,
        73 => :help, 117 => :help, 230 => :alt, 71 => :no_scroll, 57 => :caps_lock,
        63 => :forty_eighty, 72 => :forty_eighty, 78 => :run_stop
      }.freeze

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

      # The C128's key for the scancode in the C128's +mode+, :c128 or
      # :c64: one of C128_OTHERS, ESC, or the C64's.
      def self.c128_key(scancode, mode)
        return :esc if scancode == ESCAPE && mode == :c128

        C128_OTHERS[scancode] || c64_key(scancode)
      end

      # The character the key types on a US layout: a letter, a capital
      # with `shift`, or a digit, and "" for any other key.
      def self.character(scancode, shift)
        if scancode.between?(4, 29)
          letter = (97 + scancode - 4).chr
          shift ? letter.upcase : letter
        elsif scancode.between?(30, 39)
          "1234567890"[scancode - 30]
        else
          ""
        end
      end

      def self.arrows(scancode) = ARROWS[scancode] || :none

      def self.wasd(scancode) = WASD[scancode] || :none

      def self.joystick?(scancode) = ARROWS.key?(scancode) || WASD.key?(scancode)
    end
  end
end
