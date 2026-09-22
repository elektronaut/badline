# frozen_string_literal: true

module Badline
  module Storage
    # Raw datasette pulse stream. The header holds the signature, the
    # version at $0c and the data size at $10; the data runs from $14, every
    # byte the time to the next falling edge on the tape read line, in units
    # of 8 cycles.
    class TAP
      class FormatError < StandardError; end

      SIGNATURE = "C64-TAPE-RAW".bytes.freeze
      HEADER_SIZE = 0x14
      OVERFLOW = 0x100 * 8

      attr_reader :version

      def initialize(path)
        @bytes = File.binread(path).bytes
        raise FormatError, "Missing TAP signature" unless @bytes[0, SIGNATURE.length] == SIGNATURE

        @version = @bytes[0x0c].to_i
        raise FormatError, "Unsupported TAP version #{@version}" if @version > 1

        @end = tape_end
        rewind
      end

      def rewind
        @pos = HEADER_SIZE
      end

      def end? = @pos >= @end

      # Cycles until the next falling edge, or nil once the tape has run out.
      def next_pulse
        return if end?

        byte = @bytes[@pos]
        @pos += 1
        return byte * 8 unless byte.zero?

        # $00 is an overflow in version 0 and a 24-bit cycle count in
        # version 1.
        version.zero? ? OVERFLOW : long_pulse
      end

      private

      # The stated size disagrees with the file in the wild, and a few dumps
      # leave it zeroed altogether.
      def tape_end
        size = little_endian(@bytes[0x10, 4] || [])
        size.zero? ? @bytes.length : [HEADER_SIZE + size, @bytes.length].min
      end

      def long_pulse
        bytes = @bytes[@pos, 3]
        @pos += 3
        bytes&.length == 3 ? little_endian(bytes) : OVERFLOW
      end

      def little_endian(bytes)
        bytes.each_with_index.sum { |byte, i| byte << (8 * i) }
      end
    end
  end
end
