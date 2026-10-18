# frozen_string_literal: true

module Badline
  module Drives
    class Model8050
      # Each chip a class of its own, so each keeps one type of peripheral.

      # UC1, on the IEEE-488 data lines.
      class DataRIOT < Chips::RIOT
      end

      # UE1, on the control lines, the jumpers and the LEDs.
      class ControlRIOT < Chips::RIOT
      end

      # UM3, the controller's VIA, at $0040.
      class ControllerVIA < Chips::VIA
      end

      # UK3, the controller's 6530, its ROM the controller's program.
      class ControllerRRIOT < Chips::RRIOT
      end

      # The interface processor's 6502, UN1, on the IPBus.
      class IPCPU
        include Badline::Chips::CPU::Core
        include Engine::IdleCPU
      end

      # The floppy controller's 6502, UH3, on the FDCBus.
      class FDCCPU
        include Badline::Chips::CPU::Core
        include Engine::IdleCPU
      end
    end
  end
end
