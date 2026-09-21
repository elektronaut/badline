# frozen_string_literal: true

module Badline
  module KernalTrap
    # One open channel on the virtual drive, holding a file, a block buffer
    # or the command channel's status message. It gives out one byte at a
    # time and flags the last one, so the bus can raise EOI with it.
    class Channel
      attr_accessor :pointer

      def initialize(bytes = [])
        replace(bytes)
      end

      def replace(bytes)
        @bytes = bytes
        @pointer = 0
      end

      def exhausted?
        @pointer >= @bytes.length
      end

      def read
        return if exhausted?

        byte = @bytes[@pointer]
        @pointer += 1
        [byte, exhausted?]
      end
    end
  end
end
