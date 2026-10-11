# frozen_string_literal: true

module Badline
  module Drive
    # Fast serial on a drive with a CIA, the 1571's 6526 or the 1581's
    # 8520: through buffers a port line turns round, the CIA's CNT drives
    # SRQ and its SP drives DATA, or it hears them. The drive pushes its
    # pins into the bus as they move, and hears the host's as the host
    # pushes them, pin by pin, so each byte goes through both shift
    # registers bit by bit. The CIA takes no part in a pass of the idle
    # loop, and any access to it, or the host moving its fast serial pins,
    # wakes the drive.
    #
    # A model includes it beside Core, and calls turn_fast_serial when its
    # direction line moves and drive_fast_serial each cycle the buffers
    # face out. Its serial_output carries @fast_output above its port.
    module FastSerial
      # Whether the buffers face out, the drive's CIA driving DATA and SRQ.
      attr_reader :fast_serial_out

      # The host moved its fast serial pins: the CIA hears SRQ on CNT and
      # DATA on SP while the buffers face in.
      def fast_lines_moved
        settle!
        hear_fast_serial unless @fast_serial_out
      end

      private

      def init_fast_serial
        @fast_serial_out = false
        @fast_output = 0
      end

      # The buffers turned round: outwards the CIA's pins drive the lines,
      # and inwards they let go and hear them.
      def turn_fast_serial(out)
        @fast_serial_out = out
        return unless @serial_bus

        push_fast_output(out ? fast_pins : 0)
        hear_fast_serial unless out
      end

      def drive_fast_serial
        low = fast_pins
        push_fast_output(low) if low != @fast_output
      end

      # The lines the CIA's CNT and SP pull while its serial port drives
      # them.
      def fast_pins
        serial = @cia.serial
        return 0 unless serial.output?

        low = serial.cnt ? 0 : IECBus::DRIVE_FAST_SRQ
        serial.sp_out ? low : low | IECBus::DRIVE_FAST_DATA
      end

      def push_fast_output(low)
        @fast_output = low
        @serial_bus&.drives_fast_moved!
      end

      def hear_fast_serial
        low = @serial_bus.low_lines
        serial = @cia.serial
        serial.cnt_in = low.nobits?(IECBus::SRQ)
        serial.sp_in = low.nobits?(IECBus::DATA)
      end
    end
  end
end
