# frozen_string_literal: true

module Badline
  class Drive1541
    # VIA 2, the one facing the disk mechanism. Its port B drives the
    # Mechanism, which hears the lines after every write and reset, since
    # ORB, DDRB and the ACR can all change them.
    class DiskVIA < VIA
      def initialize(start:, mechanism:)
        @mechanism = mechanism
        super(start:, peripheral: mechanism)
      end

      def reset!
        super
        @mechanism.port_b_written(port_b_output)
      end

      def poke(addr, value)
        super
        @mechanism.port_b_written(port_b_output)
      end
    end
  end
end
