# frozen_string_literal: true

module Badline
  class C64
    class Bus
      # The 6510's port under port.* in a keyed snapshot module
      # (Snapshot::Keyed, BL-CPU), and the bus once its memories, the port
      # and the cartridge are loaded: the banks the CPU and the VIC see are
      # worked out again.
      module KeyedState
        def save_port_fields(out) = @cpu_port.save_fields(out, "port.")

        def load_port_fields(input) = @cpu_port.load_fields(input, "port.")

        def restored! = update_overlays!
      end

      include KeyedState
    end
  end
end
