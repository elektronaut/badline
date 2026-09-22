# frozen_string_literal: true

module Badline
  module InstructionSet
    module Stack
      # Push accumulator onto the stack.
      #
      # Opcodes:
      #   $48 - implied - 3 cycles
      def pha(_addr, _value)
        stack_push(@a)
      end

      # Push processor status onto the stack.
      #
      # Opcodes:
      #   $08 - implied - 3 cycles
      def php(_addr, _value)
        stack_push(p | 0b00010000)
      end

      # Pull accumulator from stack.
      #
      # Opcodes:
      #   $68 - implied - 4 cycles
      def pla(_addr, _value)
        @a = stack_pull
        update_number_flags(@a)
      end

      # Pull processor status from stack.
      #
      # Opcodes:
      #   $28 - implied - 4 cycles
      def plp(_addr, _value)
        status.value = stack_pull & 0b11101111
      end

      private

      def stack_pull
        @stack_pointer = (@stack_pointer + 1) & 0xff
        @memory.peek(stack_address)
      end

      def stack_push(value)
        write_byte(stack_address, value)
        @stack_pointer = (@stack_pointer - 1) & 0xff
      end
    end
  end
end
