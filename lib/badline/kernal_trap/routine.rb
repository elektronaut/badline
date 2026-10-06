# frozen_string_literal: true

module Badline
  module KernalTrap
    # Base class for the PC traps on KERNAL routines. Holds the device
    # number they answer for, the layout of the KERNAL they trap, and the
    # return that stands in for the trapped routine's RTS.
    class Routine
      include IntegerHelper

      DEVICE = 8

      # Timer B's latch high byte as ISOUR and ACPTR set it, and the
      # control value both start it with: force load, one-shot, start.
      ISOUR_TIMEOUT = 0x04
      ACPTR_TIMEOUT = 0x01
      TIMER_ONE_SHOT_START = 0x19

      def initialize(cpu:, bus:, layout:)
        @cpu = cpu
        @bus = bus
        @layout = layout
      end

      private

      def kernal_mapped?
        @layout.kernal_mapped?(@bus)
      end

      # The ROM times each byte on the serial bus with CIA 1's timer B,
      # started one-shot with the high byte of its latch set: ISOUR_TIMEOUT
      # for a byte sent, ACPTR_TIMEOUT for one received.
      def time_serial_byte(timer_high)
        @bus.poke(0xdc07, timer_high)
        @bus.poke(0xdc0f, TIMER_ONE_SHOT_START)
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
