# frozen_string_literal: true

module Badline
  module InstructionSet
    module Flag
      # Clear carry flag.
      #
      # Opcodes:
      #   $18 - implied - 2 cycles
      def clc(_addr, _value)
        write_flag(:carry, false)
      end

      # Clear decimal mode flag.
      #
      # Opcodes:
      #   $D8 - implied - 2 cycles
      def cld(_addr, _value)
        write_flag(:decimal, false)
      end

      # Clear interrupt disable flag.
      #
      # Opcodes:
      #   $58 - implied - 2 cycles
      def cli(_addr, _value)
        write_flag(:interrupt, false)
      end

      # Clear overflow flag.
      #
      # Opcodes:
      #   $B8 - implied - 2 cycles
      def clv(_addr, _value)
        write_flag(:overflow, false)
      end

      # Set carry flag.
      #
      # Opcodes:
      #   $38 - implied - 2 cycles
      def sec(_addr, _value)
        write_flag(:carry, true)
      end

      # Set decimal mode flag.
      #
      # Opcodes:
      #   $F8 - implied - 2 cycles
      def sed(_addr, _value)
        write_flag(:decimal, true)
      end

      # Set interrupt disable flag.
      #
      # Opcodes:
      #   $78 - implied - 2 cycles
      def sei(_addr, _value)
        write_flag(:interrupt, true)
      end

      private

      # The flag write lands on the instruction's second cycle. Going through
      # Status#set rather than the named setter keeps the block's value an
      # integer: Spinel mistypes a cycle whose block tails in a boolean
      # assignment.
      def write_flag(name, enabled)
        cycle { status.set(name, enabled) }
      end
    end
  end
end
