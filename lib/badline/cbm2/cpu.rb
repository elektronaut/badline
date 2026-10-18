# frozen_string_literal: true

module Badline
  class CBM2
    # The 6509: a 6502 core with four more address lines, which pick one of
    # the Bus's sixteen segments. Every access goes to the execution
    # segment, but the ones at the address LDA (zp),Y and STA (zp),Y index,
    # their data and the dummy read before it, which go to the indirection
    # segment: the opcode and the zero-page pointer stay in the execution
    # segment. Interrupts leave both segments alone.
    class CPU
      include Badline::Chips::CPU::Core

      def initialize(memory, debug: false)
        super
        @indirect = false
      end

      def reset!
        super
        @indirect = false
      end

      private

      def op_pointer_high_y
        super
        @indirect = @operation == :lda || @operation == :sta
      end

      def op_idx_dummy
        return super unless @indirect

        @memory.select_indirect!
        super
        @memory.select_execute!
      end

      def op_mem_read
        return super unless @indirect

        @indirect = false
        @memory.select_indirect!
        super
        @memory.select_execute!
      end

      def op_mem_write
        return super unless @indirect

        @indirect = false
        @memory.select_indirect!
        super
        @memory.select_execute!
      end
    end
  end
end
