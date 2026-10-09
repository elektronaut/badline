# frozen_string_literal: true

module Badline
  class Drive1571
    # The drive's 6502, on the drive's Bus.
    class CPU
      include Badline::CPU::Core
      include Drive::IdleCPU
    end
  end
end
