# frozen_string_literal: true

module Badline
  class C64
    class Bus
      # The bus once its memories, the CPU port and the cartridge are loaded
      # from a keyed snapshot (Snapshot::Keyed): the banks the CPU and the
      # VIC see are worked out again.
      module KeyedState
        def restored! = update_overlays!
      end

      include KeyedState
    end
  end
end
