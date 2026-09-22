# frozen_string_literal: true

module Badline
  module InstructionSet
    module IncDec
      # Decrements memory location by one.
      #
      # Opcodes:
      #   $C6 - zeropage   - 5 cycles
      #   $CE - absolute   - 6 cycles
      #   $D6 - zeropage_x - 6 cycles
      #   $DE - absolute_x - 7 cycles
      def dec(addr, value)
        v = resolve(value)
        result = (v - 1) & 0xff
        write_modified(addr, v, result)
        update_number_flags(result)
      end

      # Decrements X register by one.
      #
      # Opcodes:
      #   $CA - implied - 2 cycles
      def dex(_addr, _value)
        @x = (@x - 1) & 0xff
        update_number_flags(@x)
      end

      # Decrements Y register by one.
      #
      # Opcodes:
      #   $88 - implied - 2 cycles
      def dey(_addr, _value)
        @y = (@y - 1) & 0xff
        update_number_flags(@y)
      end

      # Increments memory location by one.
      #
      # Opcodes:
      #   $E6 - zeropage   - 5 cycles
      #   $EE - absolute   - 6 cycles
      #   $F6 - zeropage_x - 6 cycles
      #   $FE - absolute_x - 7 cycles
      def inc(addr, value)
        v = resolve(value)
        result = (v + 1) & 0xff
        write_modified(addr, v, result)
        update_number_flags(result)
      end

      # Increments X register by one.
      #
      # Opcodes:
      #   $E8 - implied - 2 cycles
      def inx(_addr, _value)
        @x = (@x + 1) & 0xff
        update_number_flags(@x)
      end

      # Increments Y register by one.
      #
      # Opcodes:
      #   $C8 - implied - 2 cycles
      def iny(_addr, _value)
        @y = (@y + 1) & 0xff
        update_number_flags(@y)
      end
    end
  end
end
