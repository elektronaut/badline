# frozen_string_literal: true

module Badline
  class Drive1541
    # The Mechanism's BYTE READY line: to VIA 2's CA1, to the CPU's SO pin
    # through SOE, and on the 1571 to a latch VIA 1's PA7 reads.
    module ByteReady
      # VIA 2, which DiskVIA plugs in.
      attr_writer :via

      # Whether BYTE READY reached SO for the CPU to sample on the drive's
      # next cycle.
      attr_accessor :so_pending

      # Whether SO is pending, which the drive's cycle samples and clears.
      def take_so
        so = @so_pending
        @so_pending = false
        so
      end

      # The read electronics signal a whole GCR byte. BYTE READY pulls VIA
      # 2's CA1 low, a falling edge that sets its flag and, with latching
      # on, latches port A. It reaches the CPU's SO pin while VIA 2's CA2
      # (SOE) is high, which lets the DOS spin on BVC for each byte. The CPU
      # samples SO on the next cycle.
      def byte_ready!
        @byte_latched = true
        @via.ca1 = false
        @so_pending = true if @via.ca2_output
      end

      # BYTE READY lets go of CA1 with the next bit.
      def byte_ready_ended!
        @via.ca1 = true
      end

      # Whether BYTE READY has come since the CPU last read VIA 2, as the
      # 1571 latches it for VIA 1's PA7.
      def byte_latched? = @byte_latched

      # A read of VIA 2 clears the 1571's BYTE READY latch.
      def release_byte_latch
        @byte_latched = false
      end
    end
  end
end
