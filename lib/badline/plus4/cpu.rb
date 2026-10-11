# frozen_string_literal: true

module Badline
  class Plus4
    # The 7501 or 8501, a 6510 core without an NMI pin, on the Plus4::Bus.
    class CPU
      include Badline::Chips::CPU::Core
    end
  end
end
