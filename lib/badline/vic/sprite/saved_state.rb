# frozen_string_literal: true

module Badline
  class VIC < Cycleable
    class Sprite
      # The sprite's save_state and load_state.
      module SavedState
        # The shift register, MC, MCBASE, the expansion flip-flop and whether
        # the sprite shows, for a VICE snapshot.
        attr_reader :sr, :mc, :mcbase, :exp_ff, :display_on

        # Sets MC, MCBASE, the expansion flip-flop, whether the sprite's DMA
        # runs and whether it shows, as a VICE snapshot gives them.
        def restore_counters(counter, base, expanded, dma, shows)
          @mc = counter
          @mcbase = base
          @exp_ff = expanded
          @dma = dma
          @display_on = shows
        end

        def save_state(out)
          out.boolean(@dma).boolean(@display_on).int(@mcbase).int(@mc).boolean(@exp_ff).optional_int(@crunched_mc)
          out.int(@bits).boolean(@row_ready).optional_int(@prev_bits).boolean(@first_byte_lost).boolean(@blind)
          out.int(@show_from).optional_int(@stop_x)
          out.ints(@codes).int(@leftmost).int(@span).ints(@reload_codes).int(@reload_leftmost).int(@reload_span)
          out.int(@sr).int(@latch).boolean(@mc_flop).boolean(@xe_flop)
        end

        def load_state(input)
          load_counters(input)
          @show_from = input.int
          @stop_x = input.optional_int
          input.ints_into(@codes)
          @leftmost = input.int
          @span = input.int
          input.ints_into(@reload_codes)
          @reload_leftmost = input.int
          @reload_span = input.int
          @sr = input.int
          @latch = input.int
          @mc_flop = input.boolean?
          @xe_flop = input.boolean?
        end

        private

        def load_counters(input)
          @dma = input.boolean?
          @display_on = input.boolean?
          @mcbase = input.int
          @mc = input.int
          @exp_ff = input.boolean?
          @crunched_mc = input.optional_int
          @bits = input.int
          @row_ready = input.boolean?
          @prev_bits = input.optional_int
          @first_byte_lost = input.boolean?
          @blind = input.boolean?
        end
      end
    end
  end
end
