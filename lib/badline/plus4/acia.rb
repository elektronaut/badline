# frozen_string_literal: true

module Badline
  class Plus4
    # The Plus/4's 6551 ACIA at $FD00-$FD0F, its four registers repeated,
    # as a stub with nothing on the line: it never receives, its
    # transmitter is always empty, and it never interrupts. The command and
    # control registers keep what is written to them, and a write to the
    # status register, a programmed reset, clears the command register's
    # low five bits.
    class ACIA
      STATUS = 0x10

      attr_reader :command, :control

      def initialize
        reset!
      end

      def reset!
        @command = 0
        @control = 0
      end

      def irq? = false

      def peek(addr)
        case addr & 0x03
        when 1 then STATUS
        when 2 then @command
        when 3 then @control
        else 0
        end
      end

      def poke(addr, value)
        case addr & 0x03
        when 1 then @command &= 0xe0
        when 2 then @command = value
        when 3 then @control = value
        end
      end
    end
  end
end
