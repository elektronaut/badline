# frozen_string_literal: true

module Badline
  class VIA
    # One port's pair of control lines, CA1 and CA2 or CB1 and CB2, set up
    # by a nibble of the peripheral control register, and their two
    # interrupt flags. Bit 0 picks the active edge of C1, rising when set.
    # Bits 3-1 pick the C2 mode:
    #
    #   000 input, falling edge    100 handshake output
    #   001 independent, falling   101 pulse output
    #   010 input, rising edge     110 low output
    #   011 independent, rising    111 high output
    #
    # A port access clears both flags, but an independent input keeps C2's.
    # In handshake mode C2 goes low on a port access and back high on the
    # next active C1 edge. In pulse mode it goes low for the cycle after the
    # access. Port A handshakes on reads and writes, port B on writes only.
    class ControlLines
      attr_reader :control, :c1_high, :c2_high

      # The level driven on C2, high while it is an input.
      attr_reader :c2_output

      def initialize(interrupts, c1_flag:, c2_flag:, handshake_on_read:)
        @interrupts = interrupts
        @c1_flag = c1_flag
        @c2_flag = c2_flag
        @handshake_on_read = handshake_on_read
        @c1_high = @c2_high = true
        reset!
      end

      # Back to input mode with both handshake outputs released. The input
      # levels carry over.
      def reset!
        @control = 0
        @handshake_low = false
        @pulse = 0
        drive
      end

      def control=(nibble)
        @control = nibble & 0x0f
        drive
      end

      # Only the pulse output needs the clock.
      def pulsing? = @pulse.positive?

      def cycle!
        @pulse -= 1
        drive if @pulse.zero?
      end

      def active_c1_edge?(high) = high == @control.anybits?(0x01)

      # The lines' levels and mode. Which flags they set, and whether reads
      # handshake, are the port's wiring.
      def save_state(out)
        out.int(@control).boolean(@c1_high).boolean(@c2_high).boolean(@handshake_low).int(@pulse).boolean(@c2_output)
      end

      def load_state(input)
        @control = input.int
        @c1_high = input.boolean?
        @c2_high = input.boolean?
        @handshake_low = input.boolean?
        @pulse = input.int
        @c2_output = input.boolean?
      end

      # Everything the lines hold, for comparing them at two points.
      def state = [@control, @c1_high, @c2_high, @handshake_low, @pulse, @c2_output]

      # A new C1 level. An active edge sets the flag and ends a handshake.
      def c1=(high)
        return if high == @c1_high

        @c1_high = high
        return unless active_c1_edge?(high)

        @handshake_low = false
        drive
        @interrupts.set(@c1_flag)
      end

      # A new C2 level. An active edge sets the flag while C2 is an input.
      def c2=(high)
        return if high == @c2_high

        @c2_high = high
        @interrupts.set(@c2_flag) if @control.nobits?(0x08) && high == @control.anybits?(0x04)
      end

      # A read or write of the handshaking port register.
      def access!(write)
        @interrupts.clear(independent? ? @c1_flag : @c1_flag | @c2_flag)
        return unless write || @handshake_on_read

        case @control >> 1
        when 4 then @handshake_low = true
        when 5 then @pulse = 2
        end
        drive
      end

      private

      def independent? = @control & 0x0a == 0x02

      def drive
        @c2_output = case @control >> 1
                     when 4 then !@handshake_low
                     when 5 then @pulse.zero?
                     when 6 then false
                     else true
                     end
      end
    end
  end
end
