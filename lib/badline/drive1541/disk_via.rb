# frozen_string_literal: true

module Badline
  class Drive1541
    # VIA 2, the one facing the disk mechanism. Its port B drives the
    # Mechanism, and CB2 selects its read or write mode. The mechanism
    # hears both after every write and reset, since ORB, DDRB, the ACR and
    # the PCR can all change them.
    class DiskVIA < VIA
      attr_reader :mechanism

      def initialize(start:, mechanism:)
        @mechanism = mechanism
        mechanism.via = self
        super(start:, peripheral: mechanism)
      end

      def reset!
        super
        tell_mechanism
      end

      def poke(addr, value)
        super
        tell_mechanism
      end

      private

      def tell_mechanism
        @mechanism.port_b_written(port_b_output)
        @mechanism.cb2_written(cb2_output)
      end
    end
  end
end
