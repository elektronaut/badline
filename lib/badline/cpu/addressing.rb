# frozen_string_literal: true

module Badline
  class CPU
    # Steps that read an instruction's operand bytes and work out the
    # address it operates on, which they leave in @address. Also the
    # single-step implied, accumulator and immediate instructions, and JMP.
    module Addressing
      private

      def op_implied_dummy
        @memory.peek(@program_counter)
      end

      def op_implied_exec
        @memory.peek(@program_counter)
        send(@operation, nil, nil)
        end_instruction
      end

      def op_accumulator_exec
        @memory.peek(@program_counter)
        send(@operation, :accumulator, @a)
        end_instruction
      end

      def op_immediate_read
        value = @memory.peek(@program_counter)
        @program_counter = (@program_counter + 1) & 0xffff
        send(@operation, nil, value)
        end_instruction
      end

      def op_zp
        @address = @memory.peek(@program_counter)
        @program_counter = (@program_counter + 1) & 0xffff
      end

      def op_zp_x
        @memory.peek(@address)
        @address = (@address + @x) & 0xff
      end

      def op_zp_y
        @memory.peek(@address)
        @address = (@address + @y) & 0xff
      end

      def op_abs_low
        @address = @memory.peek(@program_counter)
        @program_counter = (@program_counter + 1) & 0xffff
      end

      def op_abs_high
        @address |= @memory.peek(@program_counter) << 8
        @program_counter = (@program_counter + 1) & 0xffff
      end

      def op_abs_high_x
        high = @memory.peek(@program_counter)
        @program_counter = (@program_counter + 1) & 0xffff
        index_address(high, @x)
      end

      def op_abs_high_y
        high = @memory.peek(@program_counter)
        @program_counter = (@program_counter + 1) & 0xffff
        index_address(high, @y)
      end

      def op_idx_dummy
        @memory.peek(@dummy_address)
      end

      def op_zp_pointer
        @pointer = @memory.peek(@program_counter)
        @program_counter = (@program_counter + 1) & 0xffff
      end

      def op_pointer_x
        @memory.peek(@pointer)
        @pointer = (@pointer + @x) & 0xff
      end

      def op_pointer_low
        @address = @memory.peek(@pointer)
      end

      def op_pointer_high
        @address |= @memory.peek((@pointer + 1) & 0xff) << 8
      end

      def op_pointer_high_y
        index_address(@memory.peek((@pointer + 1) & 0xff), @y)
      end

      def op_jmp_high
        @program_counter = @address | (@memory.peek(@program_counter) << 8)
        end_instruction
      end

      def op_indirect_low
        @pointer = @address
        @address = @memory.peek(@pointer)
      end

      # The pointer's high byte never increments, so JMP ($30FF) reads its
      # target's high byte from $3000, not $3100.
      def op_indirect_high
        high = @memory.peek((@pointer & 0xff00) | ((@pointer + 1) & 0xff))
        @program_counter = @address | (high << 8)
        end_instruction
      end

      # Adds an index register to a base address. The 6502 adds to the low
      # byte first and spends the next cycle reading from that address,
      # before the carry reaches the high byte. Read instructions skip that
      # cycle when there is no carry.
      def index_address(high, index)
        low = @address
        @address = (((high << 8) | low) + index) & 0xffff
        @boundary_crossed = (low + index) > 0xff
        if @optional_dummy && !@boundary_crossed
          @index += 1
        else
          @dummy_address = (high << 8) | ((low + index) & 0xff)
        end
      end
    end
  end
end
