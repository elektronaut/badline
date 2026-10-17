# frozen_string_literal: true

module Badline
  module Frontend
    # SDL scancodes follow key positions on a US layout. They map onto the C64
    # keys, the C128's and the 264's own keys and, in joystick mode, the
    # joystick directions.
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

      # The 264's keys where they differ from the C64's: ESC on Esc, with
      # RUN/STOP on Page Down as on the C128, F1-F3 on F1-F3, HELP on F4,
      # Insert or Help, a cursor key on each arrow, and either SHIFT on the
      # one SHIFT. Page Up, RESTORE on the C64, presses nothing.
      PLUS4_OTHERS = {
        41 => :esc, 78 => :run_stop, 58 => :f1, 59 => :f2, 60 => :f3, 61 => :help, 73 => :help, 117 => :help,
        79 => :crsr_right, 80 => :crsr_left, 81 => :crsr_down, 82 => :crsr_up, 229 => :lshift, 75 => :none
      }.freeze

      # The characters the keys other than the letters type on a US
      # layout, unshifted and then shifted, and the keypad's.
      US_CHARACTERS = {
        30 => "1!", 31 => "2@", 32 => "3#", 33 => "4$", 34 => "5%", 35 => "6^", 36 => "7&", 37 => "8*", 38 => "9(",
        39 => "0)", 45 => "-_", 46 => "=+", 47 => "[{", 48 => "]}", 49 => "\\|", 51 => ";:", 52 => "'\"", 53 => "`~",
        54 => ",<", 55 => ".>", 56 => "/?", 84 => "//", 85 => "**", 86 => "--", 87 => "++", 89 => "11", 90 => "22",
        91 => "33", 92 => "44", 93 => "55", 94 => "66", 95 => "77", 96 => "88", 97 => "99", 98 => "00", 99 => "..",
        103 => "=="
      }.freeze

      # The PET's keys for the characters a host key types, on either
      # keyboard without SHIFT: each has a key of its own on the graphics
      # keyboard, where SHIFT turns it into a graphics character. ↑ and ←
      # are on ^, and on _ and `.
      PET_GRAPHICS_CHARACTERS = {
        "!" => :!, "\"" => :'"', "#" => :"#", "$" => :"$", "%" => :%, "&" => :&, "'" => :"'", "(" => :"(",
        ")" => :")", "\\" => :"\\", "^" => :up, "_" => :left, "`" => :left, "/" => :/, ":" => :":", "*" => :*,
        ";" => :";", "?" => :"?", "," => :",", "+" => :+, "@" => :"@", "[" => :"[", "]" => :"]", "<" => :<,
        ">" => :>, "-" => :-, "=" => :"=", "." => :".", "1" => :"1", "2" => :"2", "3" => :"3", "4" => :"4",
        "5" => :"5", "6" => :"6", "7" => :"7", "8" => :"8", "9" => :"9", "0" => :"0"
      }.freeze

      # The business keyboard's: the characters it types without SHIFT,
      # then those it types with it.
      PET_BUSINESS_CHARACTERS = {
        "1" => :"1", "2" => :"2", "3" => :"3", "4" => :"4", "5" => :"5", "6" => :"6", "7" => :"7", "8" => :"8",
        "9" => :"9", "0" => :"0", "-" => :-, ":" => :":", ";" => :";", "," => :",", "." => :".", "/" => :/,
        "@" => :"@", "[" => :"[", "]" => :"]", "\\" => :"\\", "^" => :up, "_" => :left, "`" => :left
      }.freeze

      PET_BUSINESS_SHIFTED = {
        "!" => :"1", "\"" => :"2", "#" => :"3", "$" => :"4", "%" => :"5", "&" => :"6", "'" => :"7", "(" => :"8",
        ")" => :"9", "=" => :-, "*" => :":", "+" => :";", "<" => :",", ">" => :".", "?" => :/
      }.freeze

      # The PET's keys that don't type a character, which keep the host's
      # SHIFT: RETURN, INST/DEL on Backspace, CLR/HOME on Home, RUN/STOP on
      # Page Down, and RVS on Control. Esc is RUN/STOP on the graphics
      # keyboard. The business keyboard's ESC, TAB, REPEAT and keypad are
      # on Esc, Tab, Page Up and the keypad.
      PET_KEYS = {
        40 => :return, 88 => :return, 42 => :delete, 44 => :space, 74 => :clr_home, 78 => :run_stop, 224 => :rvs,
        228 => :rvs
      }.freeze

      PET_BUSINESS_KEYS = {
        41 => :escape, 43 => :tab, 75 => :repeat, 89 => :kp1, 90 => :kp2, 91 => :kp3, 92 => :kp4, 93 => :kp5,
        94 => :kp6, 95 => :kp7, 96 => :kp8, 97 => :kp9, 98 => :kp0, 99 => :kp_period
      }.freeze

      # The cursor keys, CRSR ⇔ and CRSR ⇕, each with SHIFT for left or up.
      PET_CURSORS = { RIGHT => :cursor_h, LEFT => :cursor_h, DOWN => :cursor_v, UP => :cursor_v }.freeze

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

      # The 264's key for the scancode: one of PLUS4_OTHERS or the C64's.
      def self.plus4_key(scancode) = PLUS4_OTHERS[scancode] || c64_key(scancode)

      # The PET key for the scancode on the +keyboard+, :graphics or
      # :business, with the host's SHIFT down if +shift+, and how the
      # PET's SHIFT goes with it: :on or :off for a key that types the host
      # key's character or moves the cursor its way only so, and :host to
      # follow the host's. A letter is the PET's letter, and any other key
      # the PET key that types the same character, or :none.
      def self.pet_key(scancode, shift, keyboard)
        return [LETTERS[scancode - 4], :host] if scancode.between?(4, 29)

        cursor = PET_CURSORS[scancode]
        return [cursor, [LEFT, UP].include?(scancode) ? :on : :off] unless cursor.nil?

        business = keyboard == :business
        key = business ? PET_BUSINESS_KEYS[scancode] : nil
        key = PET_KEYS[scancode] if key.nil?
        key = :run_stop if key.nil? && scancode == ESCAPE
        return [key, :host] unless key.nil?

        pet_character(scancode, shift, business)
      end

      # The PET key that types the character the scancode types on a US
      # layout, and the SHIFT it takes.
      def self.pet_character(scancode, shift, business)
        characters = US_CHARACTERS[scancode]
        return %i[none host] if characters.nil?

        character = characters[shift ? 1 : 0]
        unshifted = business ? PET_BUSINESS_CHARACTERS[character] : PET_GRAPHICS_CHARACTERS[character]
        return [unshifted, :off] unless unshifted.nil?

        shifted = business ? PET_BUSINESS_SHIFTED[character] : nil
        shifted.nil? ? %i[none host] : [shifted, :on]
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
