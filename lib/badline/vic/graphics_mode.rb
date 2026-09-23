# frozen_string_literal: true

module Badline
  class VIC < Cycleable
    module GraphicsMode
      # Foreground masks depend only on the data byte, so each byte maps to a
      # precomputed frozen pattern shared by reference instead of being
      # written out pixel by pixel.
      HIRES_FG = Array.new(256) do |data|
        Array.new(8) { |i| data.anybits?(1 << (7 - i)) }.freeze
      end.freeze

      # The high bit of each 2-bit pair (10/11) is foreground.
      PAIR_FG = Array.new(256) do |data|
        Array.new(8) { |i| (data >> (6 - (i & ~1))).allbits?(0b10) }.freeze
      end.freeze

      NO_FG = HIRES_FG[0]

      module Hires
        def paint_hires(data, color, background, seq)
          fg = seq.cur_fg = HIRES_FG[data]
          colors = seq.cur_colors
          return colors.fill(background) if data.zero?

          i = 0
          while i < 8
            colors[i] = fg[i] ? color : background
            i += 1
          end
        end
      end

      # Decodes 2-bit pixel pairs into double-wide pixels, each pair indexing
      # the four colours in the mode's palette.
      module Multicolor
        def paint_pairs(data, seq)
          seq.cur_fg = PAIR_FG[data]
          colors = seq.cur_colors
          palette = @palette
          i = 0
          while i < 8
            colors[i] = colors[i + 1] = palette[(data >> (6 - i)) & 0b11]
            i += 2
          end
        end
      end

      # Each mode paints the byte a g-access read with the screen byte and
      # colour nibble it latched. The VIC reads the byte itself, in the
      # g-access column.
      class Text
        include Hires

        def paint(data, _screencode, color, seq)
          paint_hires(data, color, seq.registers.background, seq)
        end
      end

      class MulticolorText
        include Hires
        include Multicolor

        def initialize
          @palette = Array.new(4, 0)
        end

        def paint(data, _screencode, color, seq)
          registers = seq.registers
          if color.anybits?(0x08)
            palette = @palette
            palette[0] = registers.background(0)
            palette[1] = registers.background(1)
            palette[2] = registers.background(2)
            palette[3] = color & 0x07
            paint_pairs(data, seq)
          else
            paint_hires(data, color & 0x07, registers.background, seq)
          end
        end
      end

      class ExtendedBackgroundText
        include Hires

        def paint(data, screencode, color, seq)
          background = seq.registers.background((screencode >> 6) & 0b11)
          paint_hires(data, color, background, seq)
        end
      end

      class Bitmap
        include Hires

        def paint(data, screencode, _color, seq)
          foreground = (screencode >> 4) & 0x0f
          background = screencode & 0x0f
          paint_hires(data, foreground, background, seq)
        end
      end

      class MulticolorBitmap
        include Multicolor

        def initialize
          @palette = Array.new(4, 0)
        end

        def paint(data, screencode, color, seq)
          palette = @palette
          palette[0] = seq.registers.background(0)
          palette[1] = (screencode >> 4) & 0x0f
          palette[2] = screencode & 0x0f
          palette[3] = color & 0x0f
          paint_pairs(data, seq)
        end
      end

      class Null
        def paint(_data, _screencode, _color, seq)
          seq.cur_fg = NO_FG
          seq.cur_colors.fill(0)
        end
      end

      NULL_MODE = Null.new

      # Indexed by ECM/BMM/MCM; the three invalid combinations decode to
      # black.
      MODES = [
        Text.new,                   # 000 standard text
        MulticolorText.new,         # 001 multicolour text
        Bitmap.new,                 # 010 standard bitmap
        MulticolorBitmap.new,       # 011 multicolour bitmap
        ExtendedBackgroundText.new, # 100 ECM text
        NULL_MODE,                  # 101 invalid
        NULL_MODE,                  # 110 invalid
        NULL_MODE                   # 111 invalid
      ].freeze
    end
  end
end
