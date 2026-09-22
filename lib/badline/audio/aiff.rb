# frozen_string_literal: true

module Badline
  module Audio
    # AIFF, the same shape as WAV but big-endian, and with the sample rate
    # stored as an 80-bit IEEE 754 extended float.
    class AIFF < PCMWriter
      EXPONENT_BIAS = 16_383

      private

      def pack_format = "s>*"

      def header
        ["FORM", 0, "AIFF",
         "COMM", 18, 1, 0, 16].pack("a4Na4a4NnNn") +
          extended(rate) +
          ["SSND", 0, 0, 0].pack("a4NNN")
      end

      def patch
        write_at(4, [46 + data_size].pack("N"))
        write_at(22, [samples].pack("N"))
        write_at(42, [8 + data_size].pack("N"))
      end

      # Sign bit, 15-bit biased exponent, then a 64-bit mantissa that keeps
      # its leading one rather than hiding it.
      def extended(value)
        exponent = EXPONENT_BIAS + value.bit_length - 1
        mantissa = value << (64 - value.bit_length)
        [exponent, mantissa >> 32, mantissa & 0xffff_ffff].pack("nNN")
      end
    end
  end
end
