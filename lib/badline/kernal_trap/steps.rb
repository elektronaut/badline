# frozen_string_literal: true

module Badline
  module KernalTrap
    # The steps the PC traps on KERNAL routines share, on the @cpu, @bus
    # and @layout of the trap that includes them, which includes
    # IntegerHelper too: the layout's checks and timer, the zero page's
    # words, and the return that stands in for the trapped routine's RTS.
    # Routine includes them, and so does each trap that isn't a Routine,
    # so every trap class keeps its own layout's type.
    module Steps
      private

      def kernal_mapped?
        @layout.kernal_mapped?(@bus)
      end

      def zero_page = @layout.zero_page

      # The two-byte value whose low byte is at +address+.
      def peek_word(address)
        uint16(@bus.peek(address), @bus.peek(address + 1))
      end

      def poke_word(address, value)
        @bus.poke(address, low_byte(value))
        @bus.poke(address + 1, high_byte(value))
      end

      # The ROM times each byte on the serial bus with a one-shot timer
      # (Layout#time_serial_byte): Routine::ISOUR_TIMEOUT for a byte sent,
      # Routine::ACPTR_TIMEOUT for one received.
      def time_serial_byte(timer_high)
        @layout.time_serial_byte(@bus, timer_high)
      end

      def return_to_caller
        @cpu.program_counter = (uint16(pull_byte, pull_byte) + 1) & 0xffff
      end

      # Runs the ROM routines in order, each returning into the next, and
      # the last one to the trapped routine's caller
      def continue_with(first, *rest)
        rest.reverse_each { |address| push_address((address - 1) & 0xffff) }
        @cpu.program_counter = first
      end

      def push_address(address)
        push_byte(high_byte(address))
        push_byte(low_byte(address))
      end

      def push_byte(value)
        @bus.poke(0x0100 + @cpu.stack_pointer, value)
        @cpu.stack_pointer = (@cpu.stack_pointer - 1) & 0xff
      end

      def pull_byte
        @cpu.stack_pointer = (@cpu.stack_pointer + 1) & 0xff
        @bus.peek(0x0100 + @cpu.stack_pointer)
      end
    end
  end
end
