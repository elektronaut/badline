# frozen_string_literal: true

module Badline
  class Drive1581
    # What the 8520's ports read from outside the chip (1581 Service
    # Manual, schematic sheet 3; the DOS's I/O definitions):
    #
    #   PA0  side select (out)           PB0  DATA IN (in)
    #   PA1  /RDY from the mechanism     PB1  DATA OUT (out)
    #   PA2  /MOTOR (out)                PB2  CLK IN (in)
    #   PA3  device number switch 1      PB3  CLK OUT (out)
    #   PA4  device number switch 2      PB4  ATN ACK (out)
    #   PA5  power LED (out)             PB5  fast serial direction (out)
    #   PA6  activity LED (out)          PB6  /WPRT from the mechanism
    #   PA7  /DISK CHNG from the mech.   PB7  ATN IN (in)
    #
    # DATA IN, CLK IN and ATN IN come through inverters, so a pulled line
    # reads 1, as on the 1541 (Drive::SerialLines). A closed switch pulls
    # its line low, and both closed make device 8. The ports' outputs
    # read back as driven: the peripheral pulls only the inputs.
    class SerialPort
      include Drive::SerialLines

      READY = 0x02
      SWITCHES = 0x18
      DISK_CHANGE = 0x80
      PROTECT = 0x40

      def initialize(mechanism, device: 8, bus: IECBus.new)
        @mechanism = mechanism
        @switches = (0xff & ~SWITCHES) | (((device - 8) & 0x03) << 3)
        init_serial_lines(device, bus)
      end

      def read_a(_port_a, _port_b)
        value = @switches
        value &= ~READY if @mechanism.ready?
        value &= ~DISK_CHANGE if @mechanism.disk_changed?
        value
      end

      def read_b(_port_a, _port_b)
        low = @bus.low_lines(@host)
        value = 0xff & ~(SERIAL_INPUTS | PROTECT)
        value |= DATA_IN if low.anybits?(IECBus::DATA)
        value |= CLK_IN if low.anybits?(IECBus::CLK)
        value |= ATN_IN if low.anybits?(IECBus::ATN)
        @mechanism.write_protected? ? value : value | PROTECT
      end
    end
  end
end
