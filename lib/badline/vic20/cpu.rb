# frozen_string_literal: true

module Badline
  class Vic20
    # The VIC-20's 6502, on the Vic20::Bus.
    class CPU
      include Badline::CPU::Core
    end
  end
end
