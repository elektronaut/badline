# frozen_string_literal: true

module Badline
  class VIA
    # Saving and restoring a VIA for a snapshot.
    module SavedState
      # The registers, the timers, the shift register, the interrupt flags
      # and the control lines. The peripheral is the drive's wiring.
      def save_state(out)
        out.int(@ora).int(@orb).int(@ddra).int(@ddrb).int(@latch_a).int(@latch_b).int(@acr).int(@pcr)
        out.boolean(@pb6_high).boolean(@sr_uses_t2)
        @t1.save_state(out)
        @t2.save_state(out)
        @shift_register.save_state(out)
        @ifr.save_state(out)
        @ca.save_state(out)
        @cb.save_state(out)
      end

      # Puts the state back without telling the peripheral, which restores
      # its own.
      def load_state(input)
        @ora = input.int
        @orb = input.int
        @ddra = input.int
        @ddrb = input.int
        @latch_a = input.int
        @latch_b = input.int
        @acr = input.int
        @pcr = input.int
        @pb6_high = input.boolean?
        @sr_uses_t2 = input.boolean?
        @t1.load_state(input)
        @t2.load_state(input)
        @shift_register.load_state(input)
        @ifr.load_state(input)
        @ca.load_state(input)
        @cb.load_state(input)
      end
    end
  end
end
