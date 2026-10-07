# frozen_string_literal: true

module Badline
  class Vic20
    class VIC
      # The VIC's state for a snapshot: the registers and what they set, the
      # raster, the text window and its fetches, and the picture with what
      # each line fetched. The sound saves its own.
      module SavedState
        def save_state(out)
          out.marker("VIC20 VIC")
          out.ints(@registers).int(@rasterline).int(@column).int(@next_event)
          [@origin_x, @origin_y, @columns, @rows, @char_shift, @screen_base, @char_base].each { |value| out.int(value) }
          out.boolean(@window_open).boolean(@window_done)
          [@row_start, @matrix, @char_line, @text_rows].each { |value| out.int(value) }
          [@fetch_from, @fetch_to, @fetched, @slot, @code].each { |value| out.int(value) }
          @painter.save_state(out)
        end

        def load_state(input)
          input.marker("VIC20 VIC")
          input.ints_into(@registers)
          @rasterline = input.int
          @column = input.int
          @next_event = input.int
          load_window(input)
          @fetch_from = input.int
          @fetch_to = input.int
          @fetched = input.int
          @slot = input.int
          @code = input.int
          @painter.load_state(input)
        end

        private

        def load_window(input)
          @origin_x = input.int
          @origin_y = input.int
          @columns = input.int
          @rows = input.int
          @char_shift = input.int
          @screen_base = input.int
          @char_base = input.int
          @window_open = input.boolean?
          @window_done = input.boolean?
          @row_start = input.int
          @matrix = input.int
          @char_line = input.int
          @text_rows = input.int
        end
      end
    end
  end
end
