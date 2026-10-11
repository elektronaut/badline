# frozen_string_literal: true

module Badline
  module Machine
    module KeyboardBuffer
      ADDRESS = 0x0277
      COUNT = 0xc6
      CAPACITY = 10

      def type_text(text)
        codes = text.bytes.map { |b| ascii_to_petscii(b) }
        on_init { @pending_keys = codes }
      end

      private

      def feed_keyboard
        return unless ram.peek(COUNT).zero?

        chunk = @pending_keys.shift(CAPACITY)
        ram.write(ADDRESS, chunk)
        ram.poke(COUNT, chunk.length)
        @pending_keys = nil if @pending_keys.empty?
      end

      def ascii_to_petscii(byte)
        case byte
        when 0x61..0x7a then byte - 0x20
        when 0x41..0x5a then byte + 0x80
        else byte
        end
      end
    end
  end
end
