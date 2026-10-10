# frozen_string_literal: true

module Badline
  class C128
    # Fast serial: CIA 1's CNT and SP on the serial bus's SRQ and DATA,
    # through buffers MCR's FSDIR turns round. Outwards, the machine pushes
    # the lines the pins pull into the bus as they move. Inwards, CIA 1
    # hears the lines whenever a drive moves its own fast serial pins
    # (IECBus#on_fast_change).
    module FastSerial
      private

      def plug_fast_serial
        @fast_serial_out = false
        @bus.mmu.on_fast_serial_change { turn_fast_serial }
        @iec_bus.on_fast_change { hear_fast_serial unless @fast_serial_out }
      end

      # The machine's side of the serial bus each cycle: CIA 1's pins
      # pushed while FSDIR has them out, then the drives.
      def clock_serial_bus
        drive_fast_serial if @fast_serial_out
        @drive1541&.host_cycle!
        @drive1571&.host_cycle!
        @drive1581&.host_cycle!
      end

      def turn_fast_serial
        push_fast_serial
        hear_fast_serial unless @fast_serial_out
      end

      # Pushes the lines CIA 1's pins pull while FSDIR has them out. A
      # restored machine pushes them again, its CIA 1 hearing the lines as
      # it last did.
      def push_fast_serial
        @fast_serial_out = @bus.mmu.fast_serial_out?
        @iec_bus.host_fast_lines = @fast_serial_out ? fast_pins : 0
      end

      def drive_fast_serial
        @iec_bus.host_fast_lines = fast_pins
      end

      # The lines CIA 1's CNT and SP pull while its serial port drives
      # them.
      def fast_pins
        serial = @cia1.serial
        return 0 unless serial.output?

        low = serial.cnt ? 0 : IECBus::SRQ
        serial.sp_out ? low : low | IECBus::DATA
      end

      def hear_fast_serial
        low = @iec_bus.low_lines
        serial = @cia1.serial
        serial.cnt_in = low.nobits?(IECBus::SRQ)
        serial.sp_in = low.nobits?(IECBus::DATA)
      end
    end
  end
end
