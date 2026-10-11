# frozen_string_literal: true

module Badline
  class C128
    class Bus
      # The last access on the bus, which FAST mode's VIC and open bus read,
      # in a keyed snapshot module (Snapshot::Keyed) under `prefix`, and
      # what is worked out once the memories, the MMU and the chips are
      # loaded: the banks each side sees and the keyboard's extra rows.
      module KeyedState
        def save_fields(out, prefix)
          out.int("#{prefix}address", @address).int("#{prefix}data", @data)
        end

        def load_fields(input, prefix)
          @address = input.word("#{prefix}address", @address)
          @data = input.byte("#{prefix}data", @data)
        end

        def restored!
          update_overlays!
          @control_ports.extra_rows = 0xf8 | @vic.extra_keyboard_lines
        end
      end

      include KeyedState
    end
  end
end
