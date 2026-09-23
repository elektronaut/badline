# frozen_string_literal: true

module Badline
  module KernalTrap
    # Base class for the PC traps on KERNAL routines. Holds the device
    # number they answer for and the return that stands in for the trapped
    # routine's RTS.
    class Routine
      include IntegerHelper

      DEVICE = 8

      def initialize(cpu:, bus:)
        @cpu = cpu
        @bus = bus
      end

      private

      def kernal?
        @bus.io_port.kernal?
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
