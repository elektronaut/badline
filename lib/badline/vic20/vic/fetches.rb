# frozen_string_literal: true

module Badline
  class Vic20
    class VIC
      # The text window and the fetches inside it, one a cycle, which
      # Vic20::VIC includes.
      #
      # The window opens once a frame, on the line whose half matches the
      # vertical origin ($9001): the check runs every cycle, so it holds
      # from the second cycle of the first matching line to the first
      # cycle of the line after the second. On each line of the window the
      # horizontal half opens in the cycle that matches the horizontal
      # origin ($9000 bits 6-0), and the fetches start four cycles later.
      # They alternate between the video matrix, which brings the colour
      # nibble from colour RAM alongside, and the character generator, for
      # the columns $9002 asks for, latched in the second cycle of each
      # line. A row of characters is 8 lines, or 16 with $9003 bit 0 set,
      # and the window closes after the rows $9003 asks for, latched in the
      # third cycle of the frame.
      #
      # Pinned by the VIC20/split-tests timing dump of a 6561E: the first
      # matrix fetch runs 16 cycles into a line with the origin at 12, the
      # cycle a read of $9004 first sees the line counted as 0.
      module Fetches
        private

        # Moves the beam on a cycle, and returns its column.
        def advance
          column = @column + 1
          return @column = column if column < @cycles_per_line

          next_line
          0
        end

        def next_line
          @column = 0
          @blank_last_line = @blank_line
          @ycounter += 1 if @v_state == V_DISPLAY
          @h_state = H_IDLE
          @blank_line = true
          @rasterline += 1
          new_frame if @rasterline == @lines_per_frame
        end

        def new_frame
          @rasterline = 0
          @v_state = V_IDLE
          @row_count = 0
          @ycounter = 0
          @memptr = 0
          @memptr_step = 0
        end

        def open_vertical
          @v_state = @rows.zero? ? V_DONE : V_PENDING
        end

        # Inside the vertical half of the window: opens the horizontal half
        # in the cycle that matches the origin, and steps the rows at the
        # start of each line.
        def check_window(column)
          open_horizontal if @h_state == H_IDLE && (@registers[0] & 0x7f) == column
          step_row if column.zero? && @v_state == V_DISPLAY
        end

        def open_horizontal
          @h_state = H_START
          @countdown = FETCH_DELAY
          @v_state = V_DISPLAY
          @memptr_step = 0
          @columns = @pending_columns
        end

        # At the start of each line in the window: on to the next row of
        # characters once the last has had all its lines, and the window
        # closes after the last row. A line the fetches left out moves the
        # matrix on by nothing.
        def step_row
          if @ycounter == @char_height || @ycounter == 2 * @char_height
            @ycounter = 0
            @memptr_step = @blank_last_line ? 0 : @columns
            @row_count += 1
            @v_state = V_DONE if @row_count == @rows
          end
          @memptr += @memptr_step
          @memptr_step = 0
        end

        # The columns, at the start of each line, and the rows, at the
        # start of each frame.
        def latch(column)
          if column == 1
            columns = @registers[2] & 0x7f
            @pending_columns = [columns, @max_columns].min
          elsif column == 2 && @rasterline.zero?
            @rows = (@registers[3] & 0x7e) >> 1
          end
        end

        def fetch
          case @h_state
          when H_START then start_fetches
          when H_MATRIX then fetch_matrix
          when H_CHARACTER then fetch_character
          end
        end

        def start_fetches
          @countdown -= 1
          return unless @countdown.zero?

          @columns = @pending_columns
          if @columns.zero?
            @h_state = H_DONE
          else
            @blank_line = false
            @index = 0
            @h_state = H_MATRIX
          end
        end

        def fetch_matrix
          addr = (screen_base + @memptr + @index) & 0x3fff
          @code = video_read(addr)
          @code_color = @color_ram.nibble(addr)
          @h_state = H_CHARACTER
        end

        def screen_base = ((@registers[5] & 0xf0) << 6) | ((@registers[2] & 0x80) << 2)

        # The pattern goes into the pixel pipeline, to come out
        # LOAD_DELAY cycles later.
        def fetch_character
          row = @ycounter & ((@char_height >> 1) | 7)
          addr = (((@registers[5] & 0x0f) << 10) + (@code * @char_height) + row) & 0x3fff
          slot = (@tick + LOAD_DELAY) & 3
          @load_pattern[slot] = video_read(addr)
          @load_color[slot] = @code_color
          @index += 1
          @memptr_step = @index if @ycounter == @char_height - 1
          @h_state = @index >= @columns ? H_DONE : H_MATRIX
        end
      end
    end
  end
end
