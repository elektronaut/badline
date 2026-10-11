# frozen_string_literal: true

module Badline
  class C64
    class Bus
      # The 6510's port under port.* in a keyed snapshot module
      # (Snapshot::Keyed, BL-CPU), and the bus once its memories, the port
      # and the cartridge are loaded: the banks the CPU and the VIC see are
      # worked out again.
      module KeyedState
        # The RAM expansion fitted, or an Unexpanded stand-in.
        attr_reader :ram_expansion

        # Takes the cartridge out of the expansion port, as a restore does for
        # a snapshot without one.
        def detach_cartridge
          @cartridge = nil
          update_overlays!
        end

        # The 6510 port's direction and output registers, and the charge left
        # on its floating bits.
        def port_state = [@cpu_port.ddr, @cpu_port.data, @cpu_port.floating]

        # Sets the port as port_state reads it, as a snapshot restores it,
        # leaving the RAM under $00 and $01 alone.
        def restore_port(ddr, out, floating)
          @cpu_port.restore(ddr, out, floating)
        end

        def save_port_fields(out) = @cpu_port.save_fields(out, "port.")

        def load_port_fields(input) = @cpu_port.load_fields(input, "port.")

        def restored! = update_overlays!
      end

      include KeyedState
    end
  end
end
