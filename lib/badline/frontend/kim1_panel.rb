# frozen_string_literal: true

module Badline
  module Frontend
    # The KIM-1's panel as the window shows it, in place of a video chip's
    # picture: the six LED digits, the keypad laid out as the board's
    # (User Manual, figure 3.6), the SST switch, and the host keys that
    # press each. It answers what a Screen reads of a video chip: a palette
    # index a pixel, the lines changed, and the palette.
    #
    # Each frame #follow takes the cycles each segment was lit
    # (KIM1::Panel#lit_cycles). A segment lit FULL_DUTY of the time, as
    # the monitor lights each digit, shows at full brightness, and one lit
    # less dimmer, through a square root, as the eye sees it. The level
    # follows over SMOOTHING_CYCLES, the eye's persistence, so the frames'
    # beat against the program's scan doesn't flicker.
    class KIM1Panel
      WIDTH = 384
      HEIGHT = 272

      BOARD = 0
      LED = 1
      LED_LEVELS = 16
      WINDOW = 17
      KEY = 18
      KEY_HELD = 19
      KEY_TEXT = 20
      HINT = 21
      TITLE = 22
      SWITCH_ON = 23

      # The board's green, the LED segments from unlit to full, the black
      # behind them, the keys, and the text.
      PALETTE = ([0x123c22] + Array.new(LED_LEVELS) do |level|
        red = 0x2c + (((0xff - 0x2c) * level) / (LED_LEVELS - 1))
        rest = 0x08 + ((0x28 * level) / (LED_LEVELS - 1))
        (red << 16) | (rest << 8) | rest
      end + [0x000000, 0xe8e0c8, 0x8c8470, 0x101010, 0xa8c8b0, 0xffffff, 0xffd040] +
                 Array.new(8, 0)).freeze

      FULL_DUTY = 0.15
      SMOOTHING_CYCLES = 40_000.0

      # Where the digits go: the left edge of each, and their top.
      DIGIT_LEFT = [56, 100, 144, 188, 252, 296].freeze
      DIGIT_TOP = 30
      THICKNESS = 4
      LENGTH = 20

      # Each segment's place in a digit, a to g: left, top, width, height.
      SEGMENTS = [
        [THICKNESS, 0, LENGTH, THICKNESS],
        [THICKNESS + LENGTH, THICKNESS, THICKNESS, LENGTH],
        [THICKNESS + LENGTH, (2 * THICKNESS) + LENGTH, THICKNESS, LENGTH],
        [THICKNESS, (2 * THICKNESS) + (2 * LENGTH), LENGTH, THICKNESS],
        [0, (2 * THICKNESS) + LENGTH, THICKNESS, LENGTH],
        [0, THICKNESS, THICKNESS, LENGTH],
        [THICKNESS, THICKNESS + LENGTH, LENGTH, THICKNESS]
      ].freeze

      # The keypad, top row first, as on the board, with the SST switch at
      # the end of the first row.
      KEYPAD = [%w[GO ST RS SST], %w[AD DA PC +], %w[C D E F], %w[8 9 A B], %w[4 5 6 7], %w[0 1 2 3]].freeze
      KEYPAD_LEFT = 24
      KEYPAD_TOP = 100
      KEY_WIDTH = 40
      KEY_HEIGHT = 22
      KEY_GAP = 6

      # The host keys that press the panel's.
      HINTS = ["0-9, A-F: HEX", "COMMA: AD", "PERIOD: DA", "SPACE, +: +", "G, RETURN: GO", "P: PC",
               "S, ESC: ST", "R: RS", "T: SST", "CLICK: KEY", "F9: MENU"].freeze
      HINT_LEFT = 216
      HINT_TOP = 104
      HINT_LINE = 13

      attr_reader :display, :dirty_lines

      def initialize
        @display = Array.new(WIDTH * HEIGHT, BOARD)
        @dirty_lines = Array.new(HEIGHT, true)
        @font = ROM.read("character.rom")
        @brightness = Array.new(KIM1::Panel::DIGITS * 7, 0.0)
        @levels = Array.new(KIM1::Panel::DIGITS * 7, -1)
        @held = ""
        @sst = false
        @cycles = 0
        draw_board
      end

      def width = WIDTH

      def height = HEIGHT

      def palette = PALETTE

      # The whole picture: the window has nothing to crop.
      def crop = [0, 0, WIDTH, HEIGHT]

      def clear_dirty_lines!
        @dirty_lines.map! { false }
      end

      # Brings the picture up to the KIM-1 `computer`: the digits from the
      # segments' lit cycles since the last frame, and the key held and
      # the SST switch.
      def follow(computer)
        cycles = computer.cycles
        elapsed = cycles - @cycles
        @cycles = cycles
        lit = computer.panel.lit_cycles
        light(lit, elapsed) if elapsed.positive?
        held = computer.panel.held.to_s
        draw_keys(held, computer.sst) if held != @held || computer.sst != @sst
      end

      # The name of the panel's key at the window pixel `left`, `top`, as
      # KIM1::Panel::KEYS names it, ST, RS or SST, or an empty string.
      def key_at(left, top)
        across = left - KEYPAD_LEFT
        down = top - KEYPAD_TOP
        column = across / (KEY_WIDTH + KEY_GAP)
        row = down / (KEY_HEIGHT + KEY_GAP)
        return "" if across.negative? || down.negative? || column > 3 || row >= KEYPAD.size
        return "" if across % (KEY_WIDTH + KEY_GAP) >= KEY_WIDTH || down % (KEY_HEIGHT + KEY_GAP) >= KEY_HEIGHT

        KEYPAD[row][column]
      end

      # The brightness, 0 to 1, of each segment, seven to a digit.
      def brightness = @brightness.dup

      private

      def light(lit, elapsed)
        smoothing = 1.0 - Math.exp(-elapsed / SMOOTHING_CYCLES)
        lit.each_with_index do |cycles, index|
          duty = cycles.fdiv(elapsed) / FULL_DUTY
          target = Math.sqrt([duty, 1.0].min)
          level = @brightness[index] + (smoothing * (target - @brightness[index]))
          @brightness[index] = level
          shade = (level * (LED_LEVELS - 1)).round
          next if shade == @levels[index]

          @levels[index] = shade
          draw_segment(index / 7, index % 7, LED + shade)
        end
      end

      def draw_board
        text(16, 8, "MOS KIM-1", TITLE)
        box(40, 22, 304, 64, WINDOW)
        DIGIT_LEFT.each_index { |digit| 7.times { |segment| draw_segment(digit, segment, LED) } }
        @levels.map! { 0 }
        HINTS.each_with_index { |hint, line| text(HINT_LEFT, HINT_TOP + (line * HINT_LINE), hint, HINT) }
        draw_keys("", false)
      end

      def draw_segment(digit, segment, color)
        place = SEGMENTS[segment]
        box(DIGIT_LEFT[digit] + place[0], DIGIT_TOP + place[1], place[2], place[3], color)
      end

      def draw_keys(held, sst)
        @held = held
        @sst = sst
        KEYPAD.each_with_index do |names, row|
          names.each_with_index do |name, column|
            on = name == "SST" ? sst : name == held
            draw_key(KEYPAD_LEFT + (column * (KEY_WIDTH + KEY_GAP)), KEYPAD_TOP + (row * (KEY_HEIGHT + KEY_GAP)),
                     name, on)
          end
        end
      end

      def draw_key(left, top, name, on)
        face = on ? KEY_HELD : KEY
        face = on ? SWITCH_ON : KEY if name == "SST"
        box(left, top, KEY_WIDTH, KEY_HEIGHT, face)
        text(left + ((KEY_WIDTH - (name.size * 8)) / 2), top + ((KEY_HEIGHT - 8) / 2), name, KEY_TEXT)
      end

      def box(left, top, width, height, color)
        height.times do |row|
          line = top + row
          @display.fill(color, (line * WIDTH) + left, width)
          @dirty_lines[line] = true
        end
      end

      # Draws `string` from `left`, `top` in the character ROM's second set.
      def text(left, top, string, color)
        string.bytes.each_with_index do |byte, index|
          glyph(left + (index * 8), top, Painter::SCREEN_CODES[byte & 0x7f], color)
        end
      end

      def glyph(left, top, code, color)
        8.times do |row|
          bits = @font[0x800 + (code * 8) + row]
          line = top + row
          8.times { |dot| @display[(line * WIDTH) + left + dot] = color if bits.anybits?(0x80 >> dot) }
          @dirty_lines[line] = true
        end
      end
    end
  end
end
