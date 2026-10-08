# frozen_string_literal: true

module Badline
  class Z80
    # The unprefixed opcodes, which DD and FD reuse with IX or IY for HL.
    # An opcode splits into its quarter (bits 7-6), its row (5-3) and its
    # column (2-0), and each quarter of the page is regular in rows and
    # columns.
    module MainPage
      private

      def execute(opcode)
        case opcode >> 6
        when 0 then execute_low(opcode)
        when 1 then opcode == 0x76 ? @halted = true : load_register((opcode >> 3) & 7, opcode & 7)
        when 2 then alu((opcode >> 3) & 7, operand(opcode & 7))
        else execute_high(opcode)
        end
      end

      def execute_low(opcode)
        row = (opcode >> 3) & 7
        case opcode & 7
        when 0 then relative_jump(row)
        when 1 then opcode.nobits?(8) ? set_pair(row >> 1, fetch_word) : add_pair(row >> 1)
        when 2 then indirect_load(row)
        when 3 then step_pair(row)
        when 4 then modify(row, true)
        when 5 then modify(row, false)
        when 6 then load_immediate(row)
        else accumulator_operation(row)
        end
      end

      def execute_high(opcode)
        row = (opcode >> 3) & 7
        case opcode & 7
        when 0 then conditional_return(row)
        when 1 then opcode.nobits?(8) ? set_stack_pair(row >> 1, pop) : stack_and_exchange(row >> 1)
        when 2 then jump(condition?(row))
        when 3 then miscellaneous(row)
        when 4 then call(condition?(row))
        when 5 then opcode.nobits?(8) ? push_pair(row >> 1) : call_or_prefix(row >> 1)
        when 6 then alu(row, fetch_byte)
        else restart(row << 3)
        end
      end

      # The operand of the 8-bit ALU opcodes: a register or (HL).
      def operand(index)
        index == 6 ? read_byte(operand_address) : register(index)
      end

      # INC and DEC on a register or (HL).
      def modify(index, increase)
        if index == 6
          address = operand_address
          value = read_byte(address)
          @cycles += 1
          write_byte(address, increase ? increment(value) : decrement(value))
        else
          set_register(index, increase ? increment(register(index)) : decrement(register(index)))
        end
      end

      # INC and DEC on a pair, which touch no flags.
      def step_pair(row)
        @cycles += 2
        index = row >> 1
        set_pair(index, (pair(index) + (row.nobits?(1) ? 1 : -1)) & 0xffff)
      end

      def add_pair(index)
        self.hl_or_index = add16(hl_or_index, pair(index))
        @cycles += 7
      end

      def accumulator_operation(row)
        case row
        when 0, 1, 2, 3 then rotate_a(row)
        when 4 then daa
        when 5 then complement
        when 6 then assign_flags((@f & (SF | ZF | PF)) | CF | (((@last_q ^ @f) | @a) & XYF))
        else assign_flags((@f & (SF | ZF | PF)) | ((@f & CF) << 4) | ((@f & CF) ^ CF) | (((@last_q ^ @f) | @a) & XYF))
        end
      end

      def complement
        @a ^= 0xff
        assign_flags((@f & (SF | ZF | PF | CF)) | HF | NF | (@a & XYF))
      end

      def miscellaneous(row)
        case row
        when 0 then jump(true)
        when 1 then @prefix.zero? ? execute_bits(fetch_opcode) : execute_index_bits
        when 2 then output_immediate
        when 3 then input_immediate
        when 4 then exchange_stack_top
        when 5 then exchange_de_hl
        when 6 then @iff1 = @iff2 = false
        else enable_interrupts
        end
      end

      def call_or_prefix(index)
        case index
        when 0 then call(true)
        when 1 then index_prefix(1)
        when 2 then extended_prefix
        else index_prefix(2)
        end
      end

      # DD and FD: the next opcode runs with IX or IY for HL. A prefix
      # after a prefix replaces it.
      def index_prefix(prefix)
        @prefix = prefix
        @last_q = 0
        execute(fetch_opcode)
      end

      def extended_prefix
        @prefix = 0
        execute_extended(fetch_opcode)
      end

      def enable_interrupts
        @iff1 = @iff2 = true
        @after_ei = true
      end
    end
  end
end
