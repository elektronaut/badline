# frozen_string_literal: true

module Badline
  module Storage
    # Raw datasette pulse stream. The header holds the signature, the
    # version at $0c, the platform at $0d (0 C64, 1 VIC-20, 2 C16) and the
    # data size at $10; the data runs from $14, every byte the time to the
    # next falling edge on the tape read line, in units of 8 cycles. A
    # version 2 tape, the C16's and the Plus/4's, times half waves instead,
    # so it takes two bytes to the next falling edge.
    class TAP
      class FormatError < StandardError; end

      SIGNATURE = "C64-TAPE-RAW".bytes.freeze
      C16_SIGNATURE = "C16-TAPE-RAW".bytes.freeze
      HEADER_SIZE = 0x14
      OVERFLOW = 0x100 * 8

      # The file it was read from, expanded, and the file's bytes.
      attr_reader :version, :platform, :path, :bytes

      # A blank tape for `platform` at `path`, written to the host file: a
      # version 1 tape for the C64 (0) or the VIC-20 (1), and a version 2
      # C16 tape for the 264 series (2).
      def self.create(path, platform:)
        header = platform == 2 ? C16_SIGNATURE + [2] : SIGNATURE + [1]
        File.binwrite(path, (header + [platform, 0, 0, 0, 0, 0, 0]).pack("C*"))
        new(path)
      end

      # `bytes` stands in for the host file's contents, as a snapshot
      # restores the tape it holds.
      def initialize(path, bytes: nil)
        @path = File.expand_path(path)
        @bytes = bytes || File.binread(path).bytes
        signature = @bytes[0, SIGNATURE.length]
        raise FormatError, "Missing TAP signature" unless [SIGNATURE, C16_SIGNATURE].include?(signature)

        @version = @bytes[0x0c].to_i
        raise FormatError, "Unsupported TAP version #{@version}" if @version > 2

        @platform = @bytes[0x0d].to_i

        @end = tape_end
        rewind
      end

      def rewind
        @pos = HEADER_SIZE
      end

      # The offset of the next pulse byte.
      def position = @pos

      def position=(offset)
        @pos = offset
      end

      def end? = @pos >= @end

      # Records a pulse `cycles` long at the position, in place of the rest
      # of the tape: a byte of units of 8 cycles, or a zero and the 24-bit
      # cycle count for a long one (a lone zero, an overflow, on a version 0
      # tape). A version 2 tape records it as two equal halves.
      def record_pulse(cycles)
        return record(encode(cycles)) unless version == 2

        half = cycles / 2
        record(encode(cycles - half) + encode(half))
      end

      # Records a half wave `cycles` long at the position, in place of the
      # rest of the tape, as a version 2 tape times them.
      def record_half_wave(cycles)
        record(encode(cycles))
      end

      # Writes the tape back to its host file, with the data size the
      # header states.
      def save
        size = @bytes.length - HEADER_SIZE
        @bytes[0x10, 4] = [size & 0xff, (size >> 8) & 0xff, (size >> 16) & 0xff, size >> 24]
        File.binwrite(@path, @bytes.pack("C*"))
      end

      # Whether each byte times a half wave, as on a version 2 tape.
      def half_waves? = version == 2

      # Cycles until the next falling edge, or nil once the tape has run out.
      # On a version 2 tape that is two half waves, or one left at the end.
      def next_pulse
        return if end?
        return next_time unless half_waves?

        first = next_time
        end? ? first : first + next_time
      end

      # Cycles until the read line's next edge on a version 2 tape, or nil
      # once the tape has run out.
      def next_half_wave
        next_time unless end?
      end

      private

      def next_time
        byte = @bytes[@pos]
        @pos += 1
        return byte * 8 unless byte.zero?

        # $00 is an overflow in version 0 and a 24-bit cycle count from
        # version 1 on.
        version.zero? ? OVERFLOW : long_pulse
      end

      def record(times)
        @bytes.slice!(@pos..)
        @bytes.concat(times)
        @pos = @end = @bytes.length
      end

      def encode(cycles)
        units = (cycles + 4) / 8
        return [units] if units.between?(1, 0xff)
        return [0] if version.zero?

        count = [cycles, 0xffffff].min
        [0, count & 0xff, (count >> 8) & 0xff, count >> 16]
      end

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
