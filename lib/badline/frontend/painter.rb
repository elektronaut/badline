# frozen_string_literal: true

module Badline
  module Frontend
    # Draws on an SDL renderer in the C64's colours and its character ROM's
    # font: filled boxes, lines and text. The font is the ROM's second set,
    # with both cases, turned into a texture once: 16 by 16 glyphs of 8 by 8
    # pixels, white where the glyph is set and clear elsewhere, tinted to
    # the colour asked for as each glyph is drawn.
    class Painter
      GLYPH = 8
      ATLAS = GLYPH * 16

      # An opaque white pixel, in the low half of a word and in the high
      # half, where it only fits a signed 64-bit word as a negative number.
      SET = 0xffffffff
      SET_HIGH = -0x1_0000_0000

      SPACE = 0x20

      # Icons drawn in the C64's 8 by 8 cells, which take the places of the
      # first reversed glyphs, from ICON on.
      ICON = 0x80
      ICONS = {
        play: %w[.X...... .XX..... .XXX.... .XXXX... .XXXX... .XXX.... .XX..... .X......],
        pause: %w[........ .XX..XX. .XX..XX. .XX..XX. .XX..XX. .XX..XX. .XX..XX. ........],
        previous: %w[X.....X. X....XX. X...XXX. X..XXXX. X..XXXX. X...XXX. X....XX. X.....X.],
        next: %w[.X.....X .XX....X .XXX...X .XXXX..X .XXXX..X .XXX...X .XX....X .X.....X],
        left: %w[........ ....X... ...XX... ..XXX... ..XXX... ...XX... ....X... ........],
        right: %w[........ ...X.... ...XX... ...XXX.. ...XXX.. ...XX... ...X.... ........]
      }.freeze
      ICON_NAMES = ICONS.keys.freeze

      # The screen code of each printable ASCII character in the second set.
      # The rest show as a question mark.
      SCREEN_CODES = Array.new(128) do |ascii|
        if ascii.between?(0x20, 0x3f) || ascii.between?(0x41, 0x5a) then ascii
        elsif ascii == 0x40 then 0
        elsif ascii.between?(0x61, 0x7a) then ascii - 0x60
        elsif ascii == 0x5b then 27
        elsif ascii == 0x5d then 29
        elsif ascii == 0x5e then 30
        elsif ascii == 0x5f then 100
        else 63
        end
      end.freeze

      def initialize(renderer)
        @renderer = renderer
        @font = SDL.SDL_CreateTexture(renderer, SDL::PIXELFORMAT_ARGB8888, SDL::TEXTUREACCESS_STREAMING, ATLAS, ATLAS)
        SDL.SDL_SetTextureBlendMode(@font, SDL::BLENDMODE_BLEND)
        load_font
        SDL.rect_w(SDL.glyph_rect, GLYPH)
        SDL.rect_h(SDL.glyph_rect, GLYPH)
        @tint = -1
        @size = 0
      end

      def close = SDL.SDL_DestroyTexture(@font)

      def box(left, top, width, height, rgb)
        @size = 0
        rect = SDL.place_rect
        SDL.rect_x(rect, left)
        SDL.rect_y(rect, top)
        SDL.rect_w(rect, width)
        SDL.rect_h(rect, height)
        pen(rgb)
        SDL.SDL_RenderFillRect(@renderer, rect)
      end

      def line(from_x, from_y, to_x, to_y, rgb)
        pen(rgb)
        SDL.SDL_RenderDrawLine(@renderer, from_x, from_y, to_x, to_y)
      end

      # Joins the points, given as x and y in turn, with lines.
      def polyline(points, rgb)
        pen(rgb)
        i = 2
        while i < points.size
          SDL.SDL_RenderDrawLine(@renderer, points[i - 2], points[i - 1], points[i], points[i + 1])
          i += 2
        end
      end

      # Draws the text with its top left at `left` and `top`, each glyph
      # `scale` times its size, and returns the width drawn.
      def text(left, top, string, rgb, scale: 1)
        tint(rgb)
        place(top, GLYPH * scale)
        x = left
        string.each_char do |char|
          code = screen_code(char)
          glyph(code, x) unless code == SPACE
          x += @size
        end
        x - left
      end

      def self.width(string, scale: 1) = string.length * GLYPH * scale

      def icon(name, left, top, rgb, scale: 1)
        tint(rgb)
        place(top, GLYPH * scale)
        glyph(ICON + ICON_NAMES.index(name), left)
      end

      private

      def screen_code(char)
        ascii = char.ord
        ascii < 128 ? SCREEN_CODES[ascii] : 63
      end

      # Sets the row and size glyphs go at, which a run of text shares.
      def place(top, size)
        to = SDL.place_rect
        SDL.rect_y(to, top)
        return if size == @size

        @size = size
        SDL.rect_w(to, size)
        SDL.rect_h(to, size)
      end

      def glyph(code, left)
        from = SDL.glyph_rect
        SDL.rect_x(from, (code % 16) * GLYPH)
        SDL.rect_y(from, (code / 16) * GLYPH)
        to = SDL.place_rect
        SDL.rect_x(to, left)
        SDL.SDL_RenderCopy(@renderer, @font, from, to)
      end

      def pen(rgb)
        SDL.SDL_SetRenderDrawColor(@renderer, (rgb >> 16) & 0xff, (rgb >> 8) & 0xff, rgb & 0xff, 255)
      end

      def tint(rgb)
        return if rgb == @tint

        @tint = rgb
        SDL.SDL_SetTextureColorMod(@font, (rgb >> 16) & 0xff, (rgb >> 8) & 0xff, rgb & 0xff)
      end

      # Two pixels to a word, the left one in the low half, as Screen packs
      # them.
      def load_font
        rom = ROM.read("character.rom")
        words = Array.new(ATLAS * ATLAS / 2, 0)
        256.times { |code| unpack_glyph(rom[0x800 + (code * GLYPH), GLYPH], code, words) }
        ICON_NAMES.each_with_index { |name, index| unpack_glyph(icon_rows(name), ICON + index, words) }
        rect = SDL.glyph_rect
        SDL.rect_x(rect, 0)
        SDL.rect_y(rect, 0)
        SDL.rect_w(rect, ATLAS)
        SDL.rect_h(rect, ATLAS)
        SDL.SDL_UpdateTexture(@font, rect, words, ATLAS * 4)
      end

      def icon_rows(name)
        ICONS.fetch(name).map { |row| row.tr(".X", "01").to_i(2) }
      end

      def unpack_glyph(rows, code, words)
        GLYPH.times do |row|
          bits = rows[row]
          y = ((code / 16) * GLYPH) + row
          x = (code % 16) * GLYPH
          4.times do |pair|
            left = bits[7 - (pair * 2)] == 1 ? SET : 0
            right = bits[6 - (pair * 2)] == 1 ? SET_HIGH : 0
            words[(((y * ATLAS) + x) / 2) + pair] = left | right
          end
        end
      end
    end
  end
end
