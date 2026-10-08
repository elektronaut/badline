# frozen_string_literal: true

module Badline
  class C128
    class Bus
      # The bus's state for a snapshot, as AddressBus::SavedState is the
      # C64's.
      module SavedState
        # The machine's memory, the last access and everything on the bus but
        # the keyboard, the joysticks, the pot devices and CAPS LOCK, which the
        # host holds. A cartridge is already in the port, built from its setup.
        def save_state(out)
          out.marker("C128 BUS")
          out.int(@port_ddr).int(@port_out).int(@port_floating).int(@address).int(@data)
          @mmu.save_state(out)
          @ram.save_state(out)
          @color_lines.color_ram(0).save_state(out)
          @color_lines.color_ram(1).save_state(out)
          @cartridge&.save_state(out)
          @datasette.save_state(out)
          @vic.save_state(out)
          @cia1.save_state(out)
          @cia2.save_state(out)
          @sid.save_state(out)
          @vdc.save_state(out)
        end

        def load_state(input)
          input.marker("C128 BUS")
          @port_ddr = input.int
          @port_out = input.int
          @port_floating = input.int
          @address = input.int
          @data = input.int
          @mmu.load_state(input)
          @ram.load_state(input)
          @color_lines.color_ram(0).load_state(input)
          @color_lines.color_ram(1).load_state(input)
          @cartridge&.load_state(input)
          @datasette.load_state(input)
          @io_port.value = port_value
          update_overlays!
          @vic.load_state(input)
          @control_ports.extra_rows = 0xf8 | @vic.extra_keyboard_lines
          @cia1.load_state(input)
          @cia2.load_state(input)
          @sid.load_state(input)
          @vdc.load_state(input)
        end
      end
    end
  end
end
