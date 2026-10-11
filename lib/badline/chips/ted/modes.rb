# frozen_string_literal: true

module Badline
  module Chips
    class TED
      # The colours a character's pixels take in each mode, by $FF06 bits 5
      # (bitmap) and 6 (extended colour) and $FF07 bit 4 (multicolour), with
      # a pattern byte's set bits as 1 (the datasheet's "Character modes"
      # and "Bit map mode", Härsfalvi's "Talking to TED"). Each was checked
      # against xplus4 screenshots of the same registers and memory.
      #
      # - Text: 1 is the attribute's colour and luminance, bits 0-6, and 0
      #   the background, $FF15. With $FF07 bit 7 clear a pointer's bit 7
      #   reverses the character. The cursor ($FF0C-$FF0D, a character
      #   position) reverses its character, and an attribute's bit 7 makes
      #   its character flash to the background, each in turns of 16 frames
      #   of the blink counter.
      # - Multicolour text: a character whose attribute has bit 3 set takes
      #   its bits in pairs of double-width pixels, 00 the background, 01
      #   $FF16, 10 $FF17 and 11 the attribute's bits 0-2 and 4-6. Other
      #   characters show as in text. No reverse, cursor or flash.
      # - Extended colour: the pointer's bits 6-7 pick the background,
      #   $FF15-$FF18. No reverse, cursor or flash.
      # - Bitmap: 0 takes its colour from the video matrix's low nibble and
      #   its luminance from the attribute's bits 4-6, 1 from the matrix's
      #   high nibble and the attribute's bits 0-2.
      # - Multicolour bitmap: 00 the background, 01 the bitmap's 1, 10 its
      #   0, 11 $FF16, as xplus4 shows them. The datasheet gives 01 the
      #   luminance of bits 4-6 as well.
      # - Extended colour with either of the others: black.
      module Modes
        TEXT = 0x00
        MULTICOLOR_TEXT = 0x10
        BITMAP = 0x20
        MULTICOLOR_BITMAP = 0x30
        EXTENDED_COLOR = 0x40

        private

        def reset_modes
          @pixel_bits = 0
          @pixel_colors = Array.new(4, 0)
          @multicolor_pixels = false
          @blink_on = false
        end

        # The mode, $FF06 bits 5 and 6 with $FF07 bit 4.
        def mode = (@registers[0x06] & 0x60) | (@registers[0x07] & 0x10)

        # Sets the pixel bits and colours of character +index+ in +mode+.
        def character_colors(index, mode)
          pattern = @patterns[index]
          pointer = @pointers[index]
          attribute = @attributes[index]
          case mode
          when TEXT then text_colors(index, pattern, pointer, attribute)
          when MULTICOLOR_TEXT then multicolor_text_colors(pattern, attribute)
          when BITMAP then bitmap_colors(pattern, pointer, attribute)
          when MULTICOLOR_BITMAP then multicolor_bitmap_colors(pattern, pointer, attribute)
          when EXTENDED_COLOR then hires(pattern, @registers[0x15 + (pointer >> 6)] & 0x7f, attribute & 0x7f)
          else hires(0, 0, 0)
          end
        end

        # Paints pixels +from+ to +to+ of the line at +base+, of a character
        # whose first pixel is +origin+, in the colours last set.
        def paint_pixels(base, from, to, origin)
          display = @display
          bits = @pixel_bits
          colors = @pixel_colors
          multicolor = @multicolor_pixels
          x = from
          while x < to
            offset = x - origin
            color = multicolor ? colors[(bits >> (6 - (offset & 0x06))) & 0x03] : colors[(bits >> (7 - offset)) & 0x01]
            display[base + x] = color
            x += 1
          end
        end

        def hires(pattern, background, foreground)
          @pixel_bits = pattern
          @pixel_colors[0] = background
          @pixel_colors[1] = foreground
          @multicolor_pixels = false
        end

        def multicolor(pattern, color1, color2, color3)
          @pixel_bits = pattern
          colors = @pixel_colors
          colors[0] = @registers[0x15] & 0x7f
          colors[1] = color1
          colors[2] = color2
          colors[3] = color3
          @multicolor_pixels = true
        end

        def text_colors(index, pattern, pointer, attribute)
          pattern ^= 0xff if pointer >= 0x80 && !@registers[0x07].anybits?(0x80)
          if @blink_on
            pattern ^= 0xff if ((@line_position + index) & 0x3ff) == cursor_position
          elsif attribute >= 0x80
            pattern = 0
          end
          hires(pattern, @registers[0x15] & 0x7f, attribute & 0x7f)
        end

        def cursor_position = ((@registers[0x0c] & 0x03) << 8) | @registers[0x0d]

        def multicolor_text_colors(pattern, attribute)
          if attribute.anybits?(0x08)
            multicolor(pattern, @registers[0x16] & 0x7f, @registers[0x17] & 0x7f, attribute & 0x77)
          else
            hires(pattern, @registers[0x15] & 0x7f, attribute & 0x7f)
          end
        end

        def bitmap_colors(pattern, pointer, attribute)
          hires(pattern, (pointer & 0x0f) | (attribute & 0x70), (pointer >> 4) | ((attribute & 0x07) << 4))
        end

        def multicolor_bitmap_colors(pattern, pointer, attribute)
          multicolor(pattern, (pointer >> 4) | ((attribute & 0x07) << 4), (pointer & 0x0f) | (attribute & 0x70),
                     @registers[0x16] & 0x7f)
        end

        # The blink counter's carry turns the cursor and flash over.
        def blink_carry
          @blink_on = !@blink_on
        end
      end
    end
  end
end
