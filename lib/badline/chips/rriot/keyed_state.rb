# frozen_string_literal: true

module Badline
  module Chips
    class RRIOT
      # The RRIOT's fields in a keyed snapshot module (Snapshot::Keyed): the
      # RAM, the port and direction registers, and the timer under timer.
      # The ROM is the mask's, and the peripheral restores its own state.
      module KeyedState
        def save_fields(out)
          out.bytes("ram", @ram)
          out.int("ora", @ora).int("orb", @orb).int("ddra", @ddra).int("ddrb", @ddrb)
          @timer.save_fields(out, "timer.")
          out
        end

        def load_fields(input)
          input.bytes_into("ram", @ram)
          @ora = input.byte("ora", @ora)
          @orb = input.byte("orb", @orb)
          @ddra = input.byte("ddra", @ddra)
          @ddrb = input.byte("ddrb", @ddrb)
          @timer.load_fields(input, "timer.")
        end
      end

      include KeyedState
    end
  end
end
