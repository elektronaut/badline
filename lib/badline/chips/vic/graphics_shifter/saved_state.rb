# frozen_string_literal: true

module Badline
  class VIC
    class GraphicsShifter
      # The shifter's state for a snapshot.
      module SavedState
        def save_state(out)
          out.int(@next_ecm_bmm).int(@black_below).ints(@colors).booleans(@fg)
          out.int(@gbuf).int(@vbuf).int(@cbuf).int(@flop).int(@pixel)
          out.int(@mode_lookup).int(@mode_read).boolean(@late_mcm).boolean(@late_read)
        end

        def load_state(input)
          @next_ecm_bmm = input.int
          @black_below = input.int
          input.ints_into(@colors)
          input.booleans_into(@fg)
          load_buffers(input)
          @mode_lookup = input.int
          @mode_read = input.int
          @late_mcm = input.boolean?
          @late_read = input.boolean?
        end

        private

        def load_buffers(input)
          @gbuf = input.int
          @vbuf = input.int
          @cbuf = input.int
          @flop = input.int
          @pixel = input.int
        end
      end
    end
  end
end
