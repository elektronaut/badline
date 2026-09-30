# frozen_string_literal: true

module Badline
  class REU
    class DMA
      # A transfer's state for a snapshot (REU::SavedState).
      module SavedState
        # Everything a transfer holds between cycles. Before the first
        # transfer, the fields it sets on starting are empty.
        def save_state(out)
          out.int(@c64).int(@expansion).int(@length).int(@events)
          [@type, @c64_step, @expansion_step, @last, @ba_low_after_writes, @swap_byte, @held_read].each do |value|
            out.optional_int(value)
          end
          [@holding, @waiting, @stopped_after_write, @swap_write_due, @swap_read_again, @moved_all,
           @extra_cycle].each do |flag|
            out.boolean(flag)
          end
        end

        def load_state(input)
          @c64 = input.int
          @expansion = input.int
          @length = input.int
          @events = input.int
          load_steps(input)
          @holding = input.boolean?
          @waiting = input.boolean?
          @stopped_after_write = input.boolean?
          @swap_write_due = input.boolean?
          @swap_read_again = input.boolean?
          @moved_all = input.boolean?
          @extra_cycle = input.boolean?
        end

        private

        def load_steps(input)
          @type = input.optional_int
          @c64_step = input.optional_int
          @expansion_step = input.optional_int
          @last = input.optional_int
          @ba_low_after_writes = input.optional_int
          @swap_byte = input.optional_int
          @held_read = input.optional_int
        end
      end
    end
  end
end
