# frozen_string_literal: true

module Badline
  class Drive1571
    # The WD1770 floppy controller at $2000, which the DOS needs only for
    # MFM disks. Its four registers hold what's written to them and it
    # runs no commands: the status reads idle, with the motor off.
    #
    #   $2000  status (read), command (write)
    #   $2001  track
    #   $2002  sector
    #   $2003  data
    class WD1770
      def initialize
        @registers = [0, 0, 0, 0]
      end

      # Register +offset+, 0 to 3.
      def peek(offset) = offset.zero? ? 0 : @registers[offset]

      def poke(offset, value)
        @registers[offset] = value
      end

      def save_state(out)
        out.ints(@registers)
      end

      def load_state(input)
        @registers = input.ints
      end
    end
  end
end
