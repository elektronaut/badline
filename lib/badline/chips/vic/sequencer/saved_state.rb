# frozen_string_literal: true

module Badline
  class VIC
    class Sequencer
      # The sequencer's save_state and load_state.
      module SavedState
        FG_SHIFTER = -1
        PAIR_CODES = 256

        # The line buffers, the border flip-flops, the g-access ring and the
        # pixel pipeline. The foreground masks the groups point at go as
        # FG_SHIFTER for the shift register's, or their data byte in
        # GraphicsMode's HIRES_FG, or that plus 256 in its PAIR_FG. The left
        # vertical border compare goes as -1 before it has run.
        def save_state(out)
          out.int(@line).boolean(@first_csel).int(@left_vertical_border.nil? ? -1 : bit(@left_vertical_border))
          out.blob(@colors).booleans(@fg)
          @border_mask.save_state(out)
          out.ints(@cur_colors).int(fg_code(@cur_fg)).ints(@prev_colors).int(fg_code(@prev_fg))
          out.boolean(@vertical_border).boolean(@vertical_armed).boolean(@main_border)
          @color_patches.save_state(out)
          @shifter.save_state(out)
          out.int(@xscroll).int(@last_shift).int(@last_mode).boolean(@settling).boolean(@prev_fresh).boolean(@check)
          out.ints(@ring_data).ints(@ring_char).ints(@ring_color)
        end

        def load_state(input)
          load_line(input)
          @border_mask.load_state(input)
          input.ints_into(@cur_colors)
          @cur_fg = fg_pattern(input.int)
          input.ints_into(@prev_colors)
          @prev_fg = fg_pattern(input.int)
          @vertical_border = input.boolean?
          @vertical_armed = input.boolean?
          @main_border = input.boolean?
          @color_patches.load_state(input)
          @shifter.load_state(input)
          load_pipeline(input)
        end

        private

        def bit(flag) = flag ? 1 : 0

        def load_line(input)
          @line = input.int
          @first_csel = input.boolean?
          left = input.int
          @left_vertical_border = left.negative? ? nil : left == 1
          input.blob_into(@colors)
          input.booleans_into(@fg)
        end

        def load_pipeline(input)
          @xscroll = input.int
          @last_shift = input.int
          @last_mode = input.int
          @settling = input.boolean?
          @prev_fresh = input.boolean?
          @check = input.boolean?
          input.ints_into(@ring_data)
          input.ints_into(@ring_char)
          input.ints_into(@ring_color)
        end

        def fg_code(pattern)
          return FG_SHIFTER if pattern.equal?(@shifter.fg)

          hires = GraphicsMode::HIRES_FG.index { |fg| fg.equal?(pattern) }
          return hires if hires

          pair = GraphicsMode::PAIR_FG.index { |fg| fg.equal?(pattern) }
          raise ArgumentError, "a foreground mask the sequencer doesn't know" unless pair

          PAIR_CODES + pair
        end

        def fg_pattern(code)
          return @shifter.fg if code == FG_SHIFTER
          return GraphicsMode::HIRES_FG.fetch(code) if code < PAIR_CODES

          GraphicsMode::PAIR_FG.fetch(code - PAIR_CODES)
        end
      end
    end
  end
end
