# frozen_string_literal: true

module Badline
  class CPU
    # Steps that read or write an instruction's operand once its address is
    # known, plus the branch and JAM steps.
    module Operations
      private

      def op_mem_read
        send(@operation, @address, @memory.peek(@address))
        end_instruction
      end

      def op_mem_write
        send(@operation, @address, nil)
        end_instruction
      end

      # Read-modify-write instructions (ASL, INC and the like) take three
      # cycles here: read the value and compute the result, write the
      # original value back, then write the result. The instruction method
      # hands the result over through #write_modified.
      def op_rmw_read
        @value = @memory.peek(@address)
        send(@operation, @address, @value)
      end

      def op_rmw_write_original
        @memory.poke(@address, @value)
      end

      def op_rmw_write_result
        @memory.poke(@address, @rmw_result)
        end_instruction
      end

      def op_relative
        offset = @memory.peek(@program_counter)
        @program_counter = (@program_counter + 1) & 0xffff
        @address = (@program_counter + signed_int8(offset)) & 0xffff
        @branch_taken = false
        send(@operation, @address, nil)
        if @branch_taken
          # A taken branch within the same page doesn't poll on its last cycle.
          @skip_poll = true if same_page?
        else
          end_instruction
        end
      end

      def op_branch
        @memory.peek(@program_counter)
        return unless same_page?

        @program_counter = @address
        end_instruction
      end

      # A branch to another page spends an extra cycle reading from the target's low byte on the old page.
      def op_branch_fixup
        @memory.peek((@program_counter & 0xff00) | (@address & 0xff))
        @program_counter = @address
        end_instruction
      end

      def same_page?
        (@address ^ @program_counter).nobits?(0xff00)
      end

      # Runs once for each address in JAM_ADDRESSES. By the time a step runs, @index already points at the next one.
      def op_jam
        position = @index - 2
        @memory.peek(JAM_ADDRESSES[position - 1])
        end_instruction if position == JAM_ADDRESSES.length
      end
    end
  end
end
