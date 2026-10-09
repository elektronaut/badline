# frozen_string_literal: true

module Badline
  class Drive1571
    # What VIA 1's ports read from outside the chip. Port B carries the
    # serial bus inputs and the device number jumpers, as on the 1541
    # (Drive::SerialLines). Port A reads the mechanism on two inputs:
    #
    #   PA0  track 0 sensor, low while the head sits on track 1
    #   PA7  BYTE READY, latched low from a whole byte until the CPU next
    #        reads or writes VIA 2
    #
    # The DOS steps the head out until PA0 reads low with the stepper on
    # phase 0, and polls PA7 for each byte at 2 MHz, taking the byte from
    # VIA 2's port A or putting the next one there after each. PA1 (fast serial
    # direction), PA2 (side) and PA5 (1 or 2 MHz) are outputs, which
    # Drive1571 follows (SerialVIA).
    class SerialPort
      include Drive::SerialLines

      TRACK0 = 0x01
      BYTE_READY = 0x80

      def initialize(mechanism, device: 8, bus: IECBus.new)
        @mechanism = mechanism
        init_serial_lines(device, bus)
      end

      def read_a(_lines)
        value = 0xff
        value &= ~TRACK0 if @mechanism.half_track == Drive1541::Mechanism::MIN_HALF_TRACK
        value &= ~BYTE_READY if @mechanism.byte_latched?
        value
      end
    end
  end
end
