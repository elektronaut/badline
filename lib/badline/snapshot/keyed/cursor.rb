# frozen_string_literal: true

module Badline
  module Snapshot
    module Keyed
      # Reads BER numbers and byte runs from a module's payload, or from one
      # record's value, failing on anything cut short.
      class Cursor
        def initialize(bytes, name)
          @bytes = bytes
          @name = name
          @pos = 0
        end

        def done? = @pos >= @bytes.bytesize

        def remaining = @bytes.bytesize - @pos

        def ber
          value = 0
          loop do
            raise FormatError, "#{@name} holds a number too large for a snapshot" if value >= (1 << 56)

            byte = take(1).getbyte(0).to_i
            value = (value << 7) | (byte & 0x7f)
            return value if byte < 0x80
          end
        end

        def int = Keyed.unzigzag(ber)

        def take(count)
          raise FormatError, "#{@name} ends early, at byte #{@bytes.bytesize}" if count > remaining

          @bytes.byteslice(@pos, count).to_s.tap { @pos += count }
        end
      end
    end
  end
end
