# frozen_string_literal: true

module Badline
  class Drive1571
    # VIA 1, the one facing the serial bus. Its port A also selects the
    # side, the clock rate and the fast serial direction, so the drive
    # hears port A after every write and reset (Drive1571#port_a_written).
    class SerialVIA < VIA
      def initialize(start:, peripheral:, drive:)
        @drive = drive
        super(start:, peripheral:)
      end

      def reset!
        super
        @drive.port_a_written(port_a_output)
      end

      def poke(addr, value)
        super
        @drive.port_a_written(port_a_output)
      end
    end
  end
end
