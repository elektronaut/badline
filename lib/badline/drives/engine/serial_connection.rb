# frozen_string_literal: true

module Badline
  module Drives
    module Engine
      # A drive on the serial bus, beside Core: the 1541, the 1571 and the
      # 1581. It hears ATN on connecting (hear_atn) and drives the bus
      # (serial_output).
      module SerialConnection
        attr_reader :serial_bus

        # Plugs the drive into a serial bus, leaving the one it was on. A drive
        # starts out on a bus of its own, with nothing else on it.
        def connect(serial_bus)
          settle!
          @serial_bus&.detach(self)
          @serial_bus = serial_bus
          @serial_port.bus = serial_bus
          serial_bus.attach(self)
          hear_atn
        end
      end
    end
  end
end
