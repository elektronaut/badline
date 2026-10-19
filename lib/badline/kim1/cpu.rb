# frozen_string_literal: true

module Badline
  class KIM1
    # The KIM-1's 6502, U1, on the KIM1::Bus.
    #
    # With the SST switch on, the board's U26 gate pulls NMI low through
    # each opcode fetch outside K7, $1C00-$1FFF and its mirrors, where the
    # monitor runs. The CPU takes the NMI at the end of the instruction
    # that fetch starts, a 2-cycle one too, so the monitor steps a program
    # one instruction at a time (User Manual, figure 5.6).
    class CPU
      include Badline::Chips::CPU::Core

      # The K7 block's address lines, A10-A12, which the board decodes.
      K7 = 0x1c00

      # Pulls NMI if the next cycle fetches an opcode outside K7. The
      # board calls it ahead of each cycle while SST is on.
      def single_step
        @nmi = true if boundary? && (@program_counter & K7) != K7
      end
    end
  end
end
