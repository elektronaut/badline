# frozen_string_literal: true

module Badline
  class Cartridge
    class Flash
      # A Flash chip's state, for a snapshot.
      module SavedState
        STATES = %i[read program_setup autoselect programming erase_window erasing suspended chip_erase
                    program_error].freeze

        # The array, the command state, a timed operation's end on the
        # machine's clock, and the windows handed out so far, which load_state
        # builds anew.
        def save_state(out)
          out.blob(@data).int(STATES.index(@state)).int(STATES.index(@base_state)).int(@cycle).int(@toggle)
          out.optional_int(@done_at).optional_int(@programmed).optional_int(@remaining)
          out.boolean(!@erasing_sectors.nil?)
          out.ints(@erasing_sectors) if @erasing_sectors
          out.ints(@windows.keys).ints(@status_windows.keys)
        end

        def load_state(input)
          input.blob_into(@data)
          @state = STATES.fetch(input.int).to_sym
          @base_state = STATES.fetch(input.int).to_sym
          @cycle = input.int
          @toggle = input.int
          @done_at = input.optional_int
          @programmed = input.optional_int
          @remaining = input.optional_int
          @erasing_sectors = nil
          @erasing_sectors = input.ints if input.boolean?
          rebuild_windows(input.ints, input.ints)
        end
      end
    end
  end
end
