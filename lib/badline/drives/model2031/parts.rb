# frozen_string_literal: true

module Badline
  module Drives
    class Model2031
      # VIA 1, facing the IEEE-488 bus (IEEEPort), a class of its own so
      # its peripheral keeps one type, apart from the serial drives'.
      class IEEEVIA < Chips::VIA
        # DDRB, whose PB0 says whether the VIA drives ATNA (IEEEPort).
        def port_b_directions = @ddrb
      end

      # The drive CPU's bus, decoded as the 1541's (Model1541::Bus), with
      # VIA 1 an IEEEVIA.
      class Bus < Model1541::Bus
      end

      # The drive's 6502, on the drive's Bus.
      class CPU
        include Badline::Chips::CPU::Core
        include Engine::IdleCPU
      end
    end
  end
end
