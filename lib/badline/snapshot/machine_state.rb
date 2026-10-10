# frozen_string_literal: true

module Badline
  module Snapshot
    # The BADLINE module: a State from Computer#snapshot, which restores the
    # machine exactly where it was saved. VICE skips a module it doesn't
    # know.
    #
    # The payload is deflated. Inside, a little-endian 32-bit length leads
    # a run of BER-compressed integers (Ruby's pack "w"): the number of
    # values and of strings, each string's length, then the values, each
    # folded to a natural number (0, -1, 1, -2 ... as 0, 1, 2, 3 ...). The
    # strings follow, one after another.
    #
    # A State only restores in the badline version that wrote it, since
    # each chip writes its fields as it holds them.
    module MachineState
      NAME = "BADLINE"
      MAJOR = 2
      MINOR = 0

      # The values a 64-bit integer holds once encode doubles them, which a
      # native build's integers can't exceed.
      VALUES = (-(1 << 62))..((1 << 62) - 1)

      module_function

      def section(state)
        Section.new(name: NAME, major: MAJOR, minor: MINOR, data: Zlib.deflate(encode(state)))
      end

      def state(section)
        unless section.major == MAJOR
          raise FormatError, "#{NAME} #{section.version} was written by another badline version, " \
                             "and this one reads #{MAJOR}.#{MINOR}"
        end

        decode(Zlib.inflate(section.data))
      rescue Zlib::Error => e
        raise FormatError, "#{NAME} is damaged: #{e.message}"
      end

      def encode(state)
        values = state.values
        strings = state.strings
        numbers = [values.length, strings.length]
        strings.each { |string| numbers << string.bytesize }
        values.each do |value|
          raise RangeError, "#{value} is too large for a snapshot" unless VALUES.cover?(value)

          numbers << (value.negative? ? (-2 * value) - 1 : 2 * value)
        end
        index = numbers.pack("w*")
        [index.bytesize].pack("V") + index + strings.join
      end

      def decode(bytes)
        raise FormatError, "#{NAME} ends early" if bytes.bytesize < 4

        length = bytes.byteslice(0, 4).unpack1("V").to_i
        numbers = bytes.byteslice(4, length).to_s.unpack("w*").map(&:to_i)
        value_count = numbers.fetch(0, 0)
        string_count = numbers.fetch(1, 0)
        raise FormatError, "#{NAME} ends early" if numbers.length != 2 + string_count + value_count

        State.new(values(numbers, 2 + string_count), strings(bytes, 4 + length, numbers.slice(2, string_count)))
      end

      def values(numbers, from)
        Array.new(numbers.length - from) do |i|
          folded = numbers[from + i]
          folded.odd? ? -((folded + 1) / 2) : folded / 2
        end
      end

      def strings(bytes, pos, lengths)
        lengths.map do |length|
          raise FormatError, "#{NAME} ends early" if pos + length > bytes.bytesize

          bytes.byteslice(pos, length).to_s.tap { pos += length }
        end
      end
    end
  end
end
