# frozen_string_literal: true

module Badline
  class C128
    # The C128's 8502, on the C128::Bus, which holds its I/O port.
    class CPU
      include Badline::CPU::Core
    end
  end
end
