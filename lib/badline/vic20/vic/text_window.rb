# frozen_string_literal: true

module Badline
  class Vic20
    class VIC
      # The text window's rows: where it opens and closes, the video matrix
      # counter and the character line, and the registers that place the
      # window and its memory.
      module TextWindow
        private

        def new_frame
          @window_open = @window_done = false
          @row_start = @matrix = @char_line = @text_rows = 0
        end

        def open_window
          @window_open = true
          @char_line = 0
          @matrix = @row_start
        end

        # Steps to the next line of the text row, or past the row's last line
        # to the next row, closing the window after the last.
        def next_text_line
          @char_line += 1
          if @char_line < (1 << @char_shift)
            @matrix = @row_start
            return
          end

          @char_line = 0
          @row_start = @matrix
          @text_rows += 1
          return if @text_rows < @rows

          @window_open = false
          @window_done = true
        end

        # $9000 and $9002 move the window's fetches on the line, or only where
        # they end once they've started.
        def window_written
          @origin_x = @registers[0] & 0x7f
          @columns = @registers[2] & 0x7f
          bases_written
          return unless @window_open

          if @column < @fetch_from
            place_fetches
          else
            fetches_end
          end
          schedule
        end

        def rows_written(value)
          @rows = (value >> 1) & 0x3f
          @char_shift = value.anybits?(0x01) ? 4 : 3
        end

        # The video matrix at $9005 bits 7-4 and $9002 bit 7, address bits
        # 13-9, and the characters at $9005 bits 3-0, bits 13-10.
        def bases_written
          @screen_base = ((@registers[5] & 0xf0) << 6) | ((@registers[2] & 0x80) << 2)
          @char_base = (@registers[5] & 0x0f) << 10
        end
      end
    end
  end
end
