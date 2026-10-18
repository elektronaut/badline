# frozen_string_literal: true

module Badline
  module Drives
    class Model8050
      # The interface processor's two 6532s on the IEEE-488 bus
      # (Drives::IEEEBus), through MC3446 transceivers (schematic 8050001,
      # sheet 1). UC1 carries the data lines, its port A reading them and
      # its port B driving them. UE1 carries the rest:
      #
      #   PA0  ATN acknowledge (ATNA)     PB0-2  the device number jumpers
      #   PA1  NDAC out, low while set    PB3    drive 1's LED
      #   PA2  NRFD out                   PB4    drive 0's LED
      #   PA3  EOI out                    PB5    the error LED
      #   PA4  DAV out                    PB6    NDAC in
      #   PA5  EOI in                     PB7    NRFD in
      #   PA6  DAV in
      #   PA7  ATN in, high while ATN is low
      #
      # The ports read and drive the lines' levels, 0 for a low line, but
      # for NDAC out, which pulls NDAC low while set. The DOS sets it as it
      # waits for a byte and clears it once it has taken one ($C627-$C650).
      # Every input reads the bus, the drive's own lines included.
      #
      # ATN in also reaches UE1's PA7 edge detector, which the DOS arms for
      # the rising edge ($C58A), so ATN interrupts the interface processor.
      # While ATN in and ATNA differ, the board pulls NRFD and NDAC low, so
      # the drive answers ATN before the DOS gets to it, as the 2031 does.
      #
      # The device number jumpers ground PB0-2: cutting one adds its weight
      # to 8.
      #
      # The drive takes the controller's lines a host cycle late, as the
      # 2031 does: latch_host takes them at the end of each host cycle.
      class IEEEPort
        ATNA = 0x01
        NDAC_OUT = 0x02
        NRFD_OUT = 0x04
        EOI_OUT = 0x08
        DAV_OUT = 0x10
        EOI_IN = 0x20
        DAV_IN = 0x40
        ATN_IN = 0x80
        NDAC_IN = 0x40
        NRFD_IN = 0x80

        attr_reader :bus

        # The lines the controller pulled, as latch_host took them.
        attr_reader :host

        # The RIOTs on the data lines and on the control lines.
        attr_accessor :data_riot, :control_riot

        def initialize(device:, bus:)
          raise ArgumentError, "an 8050 is device 8 to 15, not #{device}" unless device.between?(8, 15)

          @jumpers = (device - 8) | 0xf8
          @host = 0
          @data_riot = nil
          @control_riot = nil
          self.bus = bus
        end

        def bus=(bus)
          @bus = bus
          latch_host
        end

        # Takes the controller's lines for the drive cycles of the next host
        # cycle.
        def latch_host
          @host = @bus.host_lines
        end

        # Whether the controller has moved ATN since the last latch_host.
        def atn_moved? = (@bus.host_lines ^ @host).anybits?(IEEEBus::ATN)

        def atn_low? = @host.anybits?(IEEEBus::ATN)

        # UC1's port A: the data lines.
        def data_lines = ~@bus.low_lines(@host) & 0xff

        # UE1's port A inputs. ATN in comes through the edge detector's own
        # pin (RIOT#pa7=), so bit 7 is left high here.
        def control_a
          low = @bus.low_lines(@host)
          value = 0xff
          value &= ~EOI_IN if low.anybits?(IEEEBus::EOI)
          value &= ~DAV_IN if low.anybits?(IEEEBus::DAV)
          value
        end

        # UE1's port B inputs: the jumpers, NDAC and NRFD.
        def control_b
          low = @bus.low_lines(@host)
          value = @jumpers
          value &= ~NDAC_IN if low.anybits?(IEEEBus::NDAC)
          value &= ~NRFD_IN if low.anybits?(IEEEBus::NRFD)
          value
        end

        # The lines the drive pulls low while ATN is low or not, as bus bits.
        def ieee_low_lines(atn)
          control = @control_riot.port_a_output
          low = ~@data_riot.port_b_output & IEEEBus::DIO
          low |= IEEEBus::EOI if control.nobits?(EOI_OUT)
          low |= IEEEBus::DAV if control.nobits?(DAV_OUT)
          low |= IEEEBus::NRFD if control.nobits?(NRFD_OUT)
          low |= IEEEBus::NDAC if control.anybits?(NDAC_OUT)
          low |= IEEEBus::NRFD | IEEEBus::NDAC if atn != control.anybits?(ATNA)
          low
        end

        # Which LEDs UE1 lights: bit 0 drive 1's, bit 1 drive 0's, bit 2 the
        # error LED.
        def leds = (@control_riot.port_b_output >> 3) & 0x07
      end

      # UC1's peripheral: the data lines on port A, port B only driving.
      class DataLines
        def initialize(port)
          @port = port
        end

        def read_a(_lines) = @port.data_lines

        def read_b(_lines) = 0xff
      end

      # UE1's peripheral: the control lines and the jumpers.
      class ControlLines
        def initialize(port)
          @port = port
        end

        def read_a(_lines) = @port.control_a

        def read_b(_lines) = @port.control_b
      end
    end
  end
end
