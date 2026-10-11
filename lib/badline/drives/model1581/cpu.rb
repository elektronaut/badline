# frozen_string_literal: true

module Badline
  module Drives
    class Model1581
      # The drive's 6502, on the drive's Bus.
      class CPU
        include Badline::Chips::CPU::Core
        include Engine::IdleCPU
      end
    end
  end
end
