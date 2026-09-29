# frozen_string_literal: true

module Badline
  class AddressBus
    # The bus's state for a snapshot: the CPU port, the RAM, colour RAM and
    # a RAM expansion, the cartridge, the datasette and the chips.
    module SavedState
      # The RAM expansion fitted, or an Unexpanded stand-in.
      attr_reader :ram_expansion

      # Takes the cartridge out of the expansion port, as a restore does for
      # a state without one.
      def detach_cartridge
        @cartridge = nil
        update_overlays!
      end

      # The 6510 port's direction and output registers, and the charge left
      # on its floating bits.
      def port_state = [@port_ddr, @port_out, @port_floating]

      # Sets the port as port_state reads it, as a snapshot restores it,
      # leaving the RAM under $00 and $01 alone.
      def restore_port(ddr, out, floating)
        @port_ddr = ddr
        @port_out = out
        @port_floating = floating
        update_port!
      end

      # The machine's memory and everything on the bus but the keyboard, the
      # joysticks and the pot devices, which the host holds. A cartridge is
      # already in the port, built from its setup (Computer#load_state).
      def save_state(out)
        out.marker("BUS")
        out.int(@port_ddr).int(@port_out).int(@port_floating)
        @ram.save_state(out)
        @color_ram.save_state(out)
        @ram_expansion.save_state(out)
        @cartridge&.save_state(out)
        @datasette.save_state(out)
        @vic.save_state(out)
        @cia1.save_state(out)
        @cia2.save_state(out)
        @sid.save_state(out)
      end

      def load_state(input)
        input.marker("BUS")
        ddr = input.int
        port_out = input.int
        floating = input.int
        @ram.load_state(input)
        @color_ram.load_state(input)
        @ram_expansion.load_state(input)
        @cartridge&.load_state(input)
        @datasette.load_state(input)
        @port_ddr = ddr
        @port_out = port_out
        @port_floating = floating
        @io_port.value = port_value
        update_overlays!
        @vic.load_state(input)
        @cia1.load_state(input)
        @cia2.load_state(input)
        @sid.load_state(input)
      end
    end

    include SavedState
  end
end
