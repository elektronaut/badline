# frozen_string_literal: true

module Badline
  module Snapshot
    module Keyed
      # Appends records to a module's payload. Each method returns self.
      class Writer
        def initialize
          @out = String.new(encoding: Encoding::BINARY)
        end

        # Raises TypeError unless `value` is an Integer, and RangeError
        # outside MachineState::VALUES.
        def int(key, value) = record(key, INT, Keyed.ber(fold(key, value)))

        def bool(key, value) = record(key, BOOL, value ? "\x01".b : "\x00".b)

        # An Array of 0..255, or a binary String.
        def bytes(key, values) = record(key, BYTES, values.is_a?(String) ? values.b : values.pack("C*"))

        def ints(key, values)
          value = Keyed.ber(values.length)
          values.each { |number| value << Keyed.ber(fold(key, number)) }
          record(key, INTS, value)
        end

        def text(key, value) = record(key, TEXT, value.b)

        # Writes nothing for nil, which a reader reads back as nil.
        def optional_int(key, value) = value.nil? ? self : int(key, value)

        # The records written so far.
        def to_s = @out.dup

        def section(name) = Section.new(name:, major: MAJOR, minor: MINOR, data: Zlib.deflate(@out))

        private

        def fold(key, value)
          raise TypeError, "#{key} is not an Integer: #{value.inspect}" unless value.is_a?(Integer)
          raise RangeError, "#{key} #{value} is too large for a snapshot" unless MachineState::VALUES.cover?(value)

          Keyed.zigzag(value)
        end

        def record(key, tag, value)
          raise ArgumentError, "#{key.inspect} is not a snapshot key" unless key.match?(KEY)

          @out << Keyed.ber(key.bytesize) << key.b << [tag].pack("C") << Keyed.ber(value.bytesize) << value
          self
        end
      end
    end
  end
end
