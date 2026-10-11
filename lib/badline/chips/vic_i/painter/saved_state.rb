# frozen_string_literal: true

module Badline
  class Vic20
    class VIC
      class Painter
        # The painter's state for a snapshot.
        module SavedState
          # The colours, the line being painted and how far, what each line
          # fetched, and the display, for a snapshot. Whether it renders is
          # the host's, and a restored display is all changed.
          def save_state(out)
            out.int(@border).int(@background).int(@aux).boolean(@reverse)
            out.int(@row).int(@painted).boolean(@written)
            out.blob(@display).blob(@patterns).blob(@colors)
            out.ints(@counts).ints(@starts).booleans(@stale).ints(@memo_keys)
          end

          def load_state(input)
            @border = input.int
            @background = input.int
            @aux = input.int
            @reverse = input.boolean?
            @row = input.int
            @painted = input.int
            @written = input.boolean?
            input.blob_into(@display)
            input.blob_into(@patterns)
            input.blob_into(@colors)
            input.ints_into(@counts)
            input.ints_into(@starts)
            input.booleans_into(@stale)
            input.ints_into(@memo_keys)
            @dirty_lines.fill(true)
          end
        end
      end
    end
  end
end
