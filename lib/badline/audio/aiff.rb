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
         "COMM", 18, channels, 0, 16].pack("a4Na4a4NnNn") +
          extended(rate) +
          ["SSND", 0, 0, 0].pack("a4NNN")
      end

      def patch
        write_at(4, [46 + data_size].pack("N"))
        write_at(22, [frames].pack("N"))
        write_at(42, [8 + data_size].pack("N"))
      end

      # Sign bit, 15-bit biased exponent, then a 64-bit mantissa that keeps
      # its leading one rather than hiding it, packed as two 32-bit halves.
      def extended(value)
        exponent = EXPONENT_BIAS + value.bit_length - 1
        [exponent, *mantissa(value, 64 - value.bit_length)].pack("nNN")
      end

      def mantissa(value, shift)
        return [value << (shift - 32), 0] if shift >= 32

        [value >> (32 - shift), (value & ((1 << (32 - shift)) - 1)) << shift]
      end
    end
  end
end
