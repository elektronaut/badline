# frozen_string_literal: true

module Badline
  module Machine
    # Typing into the KERNAL's keyboard buffer once the machine has booted.
    # The machine that includes it answers #keyboard_buffer, the Layout of
    # the KERNAL it runs, and #ram.
    module KeyboardBuffer
      # Where a KERNAL keeps its keyboard buffer (KEYD), the count of
      # characters in it (NDX), and how many it holds.
      Layout = Data.define(:address, :count, :capacity)

      # The C64's and the VIC-20's.
      C64_LAYOUT = Layout.new(address: 0x0277, count: 0xc6, capacity: 10)

      # BASIC 7.0's, in C128 mode.
      C128_LAYOUT = Layout.new(address: 0x034a, count: 0xd0, capacity: 10)

      # The 264 series KERNAL's, which sets its capacity at $053F to 10
      # ($D86E).
      PLUS4_LAYOUT = Layout.new(address: 0x0527, count: 0xef, capacity: 10)

      # The PET's, under BASIC 2 and BASIC 4. Every editor's GETIN takes
      # ten keys from it, though the CRTC editors' keyboard scans stop at
      # nine (XMAX).
      PET_LAYOUT = Layout.new(address: 0x026f, count: 0x9e, capacity: 10)

      # The PET's under BASIC 1, outside the zero page.
      PET_BASIC1_LAYOUT = Layout.new(address: 0x020f, count: 0x020d, capacity: 10)

      def type_text(text)
        codes = text.bytes.map { |b| ascii_to_petscii(b) }
        on_init { @pending_keys = codes }
      end

      private

      def feed_keyboard
        buffer = keyboard_buffer
        return unless ram.peek(buffer.count).zero?

        chunk = @pending_keys.shift(buffer.capacity)
        ram.write(buffer.address, chunk)
        ram.poke(buffer.count, chunk.length)
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
