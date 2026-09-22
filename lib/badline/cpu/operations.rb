# frozen_string_literal: true

module Badline
  class CPU
    # The operand half of the cycle sequencer: the cycles an instruction
    # spends reading, writing or branching once its address is resolved.
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

      # Read-modify-write instructions compute their result on the read
      # cycle, then put the unmodified value back on the bus before the
      # result. #write_modified leaves the result in @rmw_result.
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
          # A branch within the same page does not re-poll on its last cycle.
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

      # Crossing a page costs a fixup cycle that drives the target low byte
      # against the old high byte.
      def op_branch_fixup
        @memory.peek((@program_counter & 0xff00) | (@address & 0xff))
        @program_counter = @address
        end_instruction
      end

      def same_page?
        (@address ^ @program_counter).nobits?(0xff00)
      end

      # The plan repeats this step once per JAM_ADDRESSES entry, and
      # @index has already moved past the current one.
      def op_jam
        position = @index - 2
        @memory.peek(JAM_ADDRESSES[position - 1])
        end_instruction if position == JAM_ADDRESSES.length
      end
    end
  end
end
