# frozen_string_literal: true

module Badline
  class CPU
    # The addressing half of the cycle sequencer: one method per cycle the
    # CPU spends fetching operands and resolving the effective address.
    # Each runs its own bus access and leaves the result in @address.
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

      # An indirect jump has no carry, so a vector at $30ff reads its high
      # byte from $3000.
      def op_indirect_high
        high = @memory.peek((@pointer & 0xff00) | ((@pointer + 1) & 0xff))
        @program_counter = @address | (high << 8)
        end_instruction
      end

      # Indexing adds the index to the low byte first and drives the bus
      # with that address while the carry into the high byte resolves.
      # Instructions that only read their operand skip the cycle unless the
      # carry actually happens.
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
