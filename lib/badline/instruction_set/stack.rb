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
        cycle { @a = stack_pull }
        update_number_flags(@a)
      end

      # Pull processor status from stack.
      #
      # Opcodes:
      #   $28 - implied - 4 cycles
      def plp(_addr, _value)
        cycle { status.value = stack_pull & 0b11101111 }
      end

      # Jump to absolute address.
      #
      # Opcodes:
      #   $4C - absolute - 3 cycles
      def jmp(addr, _value)
        @program_counter = addr
      end

      # Jump to subroutine. The operand high byte is fetched only after the
      # return address has been pushed, so a JSR executing inside the stack
      # jumps via the value its own push just wrote.
      #
      # Opcodes:
      #   $20 - absolute - 6 cycles
      def jsr(addr, _value)
        return_addr = (program_counter - 1) & 0xffff
        cycle { @memory.peek(stack_address) } # internal cycle: dummy stack read
        write_byte(stack_address, high_byte(return_addr))
        write_byte(stack_address(-1), low_byte(return_addr))
        @stack_pointer = (@stack_pointer - 2) & 0xff
        @program_counter = uint16(addr, read_byte(return_addr))
      end

      # Return from interrupt.
      #
      # Opcodes:
      #   $40 - implied - 6 cycles
      def rti(_addr, _value)
        cycle do
          @stack_pointer = (@stack_pointer + 1) & 0xff
          @status.value = memory[stack_address]
          # Status#set, not the named setter: a cycle block that tails in a
          # boolean assignment is one Spinel mistypes.
          @status.set(:break, false)
        end
        @program_counter = uint16(stack_pull, stack_pull)
      end

      # Return from subroutine.
      #
      # Opcodes:
      #   $60 - implied - 6 cycles
      def rts(_addr, _value)
        cycle do
          @program_counter = (uint16(stack_pull, stack_pull) + 1) & 0xffff
        end
      end

      private

      def stack_pull
        cycle { @stack_pointer = (@stack_pointer + 1) & 0xff }
        read_byte(stack_address)
      end

      def stack_push(value)
        write_byte(stack_address, value)
        cycle { @stack_pointer = (@stack_pointer - 1) & 0xff }
      end

      def stack_push16(value)
        write_byte(stack_address, high_byte(value))
        write_byte(stack_address(-1), low_byte(value))
        cycle { @stack_pointer = (@stack_pointer - 2) & 0xff }
      end
    end
  end
end
