# frozen_string_literal: true

module Badline
  class CPU
    # Steps that use the stack: PHA, PHP, PLA, PLP, JSR, RTS and RTI.
    module StackOperations
      private

      def op_push_exec
        send(@operation, nil, nil)
        end_instruction
      end

      def op_pull_dummy
        @memory.peek(stack_address)
      end

      def op_pull_exec
        send(@operation, nil, nil)
        end_instruction
      end

      def op_pull_low
        @stack_pointer = (@stack_pointer + 1) & 0xff
        @address = @memory.peek(stack_address)
      end

      def op_pull_high
        @stack_pointer = (@stack_pointer + 1) & 0xff
        @address |= @memory.peek(stack_address) << 8
      end

      def op_rts_fixup
        @memory.peek(@address)
        @program_counter = (@address + 1) & 0xffff
        end_instruction
      end

      def op_rti_pull_status
        @stack_pointer = (@stack_pointer + 1) & 0xff
        @status.value = @memory.peek(stack_address)
        @status.break = false
      end

      def op_rti_pull_high
        @stack_pointer = (@stack_pointer + 1) & 0xff
        @program_counter = @address | (@memory.peek(stack_address) << 8)
        end_instruction
      end

      def op_jsr_low
        @address = @memory.peek(@program_counter)
        @program_counter = (@program_counter + 2) & 0xffff
      end

      def op_jsr_dummy
        @memory.peek(stack_address)
      end

      def op_jsr_push_high
        @memory.poke(stack_address, high_byte(return_address))
      end

      def op_jsr_push_low
        @memory.poke(stack_address(-1), low_byte(return_address))
        @stack_pointer = (@stack_pointer - 2) & 0xff
      end

      # JSR reads its target's high byte after pushing the return address.
      # A JSR running from the stack page can overwrite its own operand
      # with that push, and then jumps to the overwritten address.
      def op_jsr_high
        @program_counter = @address | (@memory.peek(return_address) << 8)
        end_instruction
      end

      def return_address
        (@program_counter - 1) & 0xffff
      end
    end
  end
end
