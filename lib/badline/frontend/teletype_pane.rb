# frozen_string_literal: true

module Badline
  module Frontend
    # The KIM-1's teletype as the window shows it with the TTY/KB jumper
    # fitted: a page of COLUMNS by ROWS characters in the character ROM's
    # font, printed as the teletype prints (KIM1::Teletype#output), with a
    # line of the host keys that type what the window's keys don't. RETURN
    # goes back to the line's start, LINE FEED down a line, the page
    # scrolling up from the last, and a line full at COLUMNS goes on to the
    # next. It answers what a Screen reads of a video chip, as KIM1Panel
    # does.
    class TeletypePane
      COLUMNS = 72
      ROWS = 24
      LINE = 10
      MARGIN = 8
      TOP = 22

      WIDTH = (COLUMNS * 8) + (2 * MARGIN)
      HEIGHT = 272

      PAPER = 0
      INK = 1
      HINT = 2
      CURSOR = 3
      PALETTE = [0xf2ecd8, 0x202020, 0x6c6858, 0x9c9480].freeze

      HINTS = "BACKSPACE: RUBOUT  DOWN: LINE FEED  F9: MENU"

      attr_reader :display, :dirty_lines

      def initialize
        @display = Array.new(WIDTH * HEIGHT, PAPER)
        @dirty_lines = Array.new(HEIGHT, true)
        @font = ROM.read("character.rom")
        @page = Array.new(ROWS) { Array.new(COLUMNS, 0x20) }
        @column = 0
        @row = 0
        @printed = 0
        @baud = 0
        draw_cursor(CURSOR)
      end

      def width = WIDTH

      def height = HEIGHT

      def palette = PALETTE

      def crop = [0, 0, WIDTH, HEIGHT]

      def clear_dirty_lines!
        @dirty_lines.map! { false }
      end

      # The characters on the page, a line each, without trailing spaces.
      def lines = @page.map { |row| row.map(&:chr).join.rstrip }

      # Prints what the KIM-1 `computer`'s teletype has printed since the
      # last call.
      def follow(computer)
        teletype = computer.teletype
        title(teletype.baud) if teletype.baud != @baud
        output = teletype.output
        return if output.size == @printed

        draw_cursor(PAPER)
        output[@printed, output.size - @printed].bytes.each { |byte| print_byte(byte) }
        @printed = output.size
        draw_cursor(CURSOR)
      end

      private

      def title(baud)
        @baud = baud
        box(0, 0, WIDTH, TOP, PAPER)
        text(MARGIN, 6, "KIM-1 TELETYPE, #{baud} BAUD", HINT)
        text(WIDTH - MARGIN - (HINTS.size * 8), 6, HINTS, HINT)
      end

      def print_byte(byte)
        case byte
        when 0x0d then @column = 0
        when 0x0a then line_feed
        when 0x20..0x7e then print_character(byte)
        end
      end

      def print_character(byte)
        if @column == COLUMNS
          @column = 0
          line_feed
        end
        @page[@row][@column] = byte
        glyph(MARGIN + (@column * 8), TOP + (@row * LINE), byte, INK)
        @column += 1
      end

      def line_feed
        if @row < ROWS - 1
          @row += 1
          return
        end

        @page.shift
        @page << Array.new(COLUMNS, 0x20)
        redraw_page
      end

      def redraw_page
        box(0, TOP, WIDTH, ROWS * LINE, PAPER)
        @page.each_with_index do |characters, row|
          characters.each_with_index do |byte, column|
            glyph(MARGIN + (column * 8), TOP + (row * LINE), byte, INK) unless byte == 0x20
          end
        end
      end

      def draw_cursor(color)
        column = [@column, COLUMNS - 1].min
        box(MARGIN + (column * 8), TOP + (@row * LINE) + 8, 8, 1, color)
      end

      def box(left, top, width, height, color)
        height.times do |row|
          line = top + row
          @display.fill(color, (line * WIDTH) + left, width)
          @dirty_lines[line] = true
        end
      end

      def text(left, top, string, color)
        string.bytes.each_with_index { |byte, index| glyph(left + (index * 8), top, byte, color) }
      end

      # Draws the glyph for the ASCII `byte` over a cleared cell.
      def glyph(left, top, byte, color)
        code = Painter::SCREEN_CODES[byte & 0x7f]
        8.times do |row|
          bits = @font[0x800 + (code * 8) + row]
          line = top + row
          8.times do |dot|
            @display[(line * WIDTH) + left + dot] = bits.anybits?(0x80 >> dot) ? color : PAPER
          end
          @dirty_lines[line] = true
        end
      end
    end
  end
end
