# frozen_string_literal: true

module Badline
  module Drives
    class Model1551
      # The drive's 6510T, a 6510 with an 8-bit port (Port), on the drive's
      # Bus.
      class CPU
        include Badline::Chips::CPU::Core
      end
    end
  end
end
