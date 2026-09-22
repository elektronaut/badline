# frozen_string_literal: true

module Badline
  module Audio
    # RIFF/WAVE, little-endian throughout.
    class WAV < PCMWriter
      private

      def pack_format = "s<*"

      def header
        ["RIFF", 0, "WAVE",
         "fmt ", 16, 1, 1, rate, rate * 2, 2, 16,
         "data", 0].pack("a4Va4a4VvvVVvva4V")
      end

      def patch
        write_at(4, [36 + data_size].pack("V"))
        write_at(40, [data_size].pack("V"))
      end
    end
  end
end
