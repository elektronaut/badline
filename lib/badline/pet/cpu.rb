# frozen_string_literal: true

module Badline
  class PET
    # The PET's 6502, on the PET::Bus.
    class CPU
      include Badline::Chips::CPU::Core
    end
  end
end
