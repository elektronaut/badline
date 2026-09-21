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

      def pull_byte
        @cpu.stack_pointer = (@cpu.stack_pointer + 1) & 0xff
        @bus.peek(0x0100 + @cpu.stack_pointer)
      end
    end
  end
end
