# frozen_string_literal: true

module Badline
  class Z80
    # LDI, LDD, CPI, CPD and their repeating forms. A repeating form that
    # goes round again winds the program counter back to its ED and spends
    # 5 T-states more, and bits 5 and 3 then come from the program
    # counter's high byte.
    module BlockTransfers
      private

      # ED A0-BB: the column picks LD, CP, IN or OUT, bit 3 counts down, and
      # bit 4 repeats.
      def block_operation(opcode)
        step = opcode.nobits?(0x08) ? 1 : -1
        repeat = opcode.anybits?(0x10)
        case opcode & 3
        when 0 then block_load(step, repeat)
        when 1 then block_compare(step, repeat)
        when 2 then block_input(step, repeat)
        else block_output(step, repeat)
        end
      end

      def block_load(step, repeat)
        value = read_byte(hl)
        write_byte(de, value)
        @cycles += 2
        self.hl = (hl + step) & 0xffff
        self.de = (de + step) & 0xffff
        self.bc = (bc - 1) & 0xffff
        sum = value + @a
        assign_flags((@f & (SF | ZF | CF)) | (sum & XF) | ((sum & 0x02) << 4) | (bc.zero? ? 0 : PF))
        repeat_block if repeat && !bc.zero?
      end

      def block_compare(step, repeat)
        value = read_byte(hl)
        @cycles += 5
        result = (@a - value) & 0xff
        half = (@a ^ value ^ result) & HF
        adjusted = result - (half >> 4)
        self.hl = (hl + step) & 0xffff
        self.bc = (bc - 1) & 0xffff
        @wz = (@wz + step) & 0xffff
        assign_flags((@f & CF) | NF | half | (SZ53[result] & (SF | ZF)) | (adjusted & XF) | ((adjusted & 0x02) << 4) |
                  (bc.zero? ? 0 : PF))
        repeat_block if repeat && !bc.zero? && !result.zero?
      end

      def repeat_block
        @cycles += 5
        @pc = (@pc - 2) & 0xffff
        @wz = (@pc + 1) & 0xffff
        assign_flags((@f & ~XYF) | ((@pc >> 8) & XYF))
      end
    end
  end
end
