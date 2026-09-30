# frozen_string_literal: true

module Badline
  class CPU
    # The steps at an instruction boundary: the opcode fetch that starts
    # an instruction, and the ends of one.
    module Boundary
      private

      # The first cycle of every instruction. Starts an interrupt if one was
      # pending when the previous instruction ended. Otherwise reads the
      # opcode and switches to its plan.
      def op_fetch
        return start_interrupt if @boundary_nmi || @boundary_irq

        run_traps
        opcode = @memory.peek(@program_counter)
        log(opcode) if @debug
        micro = MICROCODE[opcode]
        @operation = micro.operation
        @plan = micro.plan
        @writes = micro.writes
        @optional_dummy = micro.optional_dummy
        @index = 1
        @boundary_crossed = false
        @program_counter = (@program_counter + 1) & 0xffff
      end

      def end_instruction
        @instructions += 1
        end_sequence
      end

      # Makes the next cycle an opcode fetch, and saves the pending interrupt
      # flags for op_fetch. The next cycle polls before op_fetch runs, which
      # updates the live flags.
      def end_sequence
        @plan = FETCH_PLAN
        @writes = FETCH_WRITES
        @index = 0
        @boundary_irq = @irq_pending
        @boundary_nmi = @nmi_pending
      end

      def log(opcode)
        instruction = Instruction.find(opcode)
        puts(
          "#{@cycles}: PC: #{format16(@program_counter)} - " \
          "#{instruction.name.upcase} #{instruction.addressing_mode}"
        )
      end
    end
  end
end
