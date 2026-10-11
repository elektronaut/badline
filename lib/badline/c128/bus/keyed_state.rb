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

        # Both banks of colour RAM as bank0 and bank1.
        def save_color_fields(out)
          @color_lines.color_ram(0).save_fields(out, "bank0")
          @color_lines.color_ram(1).save_fields(out, "bank1")
        end

        def load_color_fields(input)
          @color_lines.color_ram(0).load_fields(input, "bank0")
          @color_lines.color_ram(1).load_fields(input, "bank1")
        end

        # The 8502's port, as the C64's (C64::Bus::KeyedState).
        def save_port_fields(out) = @cpu_port.save_fields(out, "port.")

        def load_port_fields(input) = @cpu_port.load_fields(input, "port.")

        def restored!
          update_overlays!
          @control_ports.extra_rows = 0xf8 | @vic.extra_keyboard_lines
        end
      end

      include KeyedState
    end
  end
end
