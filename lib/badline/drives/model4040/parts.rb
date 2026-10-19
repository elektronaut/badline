# frozen_string_literal: true

module Badline
  module Drives
    class Model4040
      # The interface processor's 6502, UN1, on the 4040's IPBus.
      class IPCPU
        include Badline::Chips::CPU::Core
        include Engine::IdleCPU
      end

      # The floppy controller's 6504, UH3, on the 8050's FDCBus. It has no
      # SO pin.
      class FDCCPU
        include Badline::Chips::CPU::Core
        include Engine::IdleCPU
      end
    end
  end
end
