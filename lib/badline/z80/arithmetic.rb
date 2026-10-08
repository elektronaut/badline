# frozen_string_literal: true

module Badline
  class Z80
    # The ALU's 8- and 16-bit arithmetic. Bits 5 and 3 of F come from the
    # result, except for CP, which takes them from the operand, and the
    # 16-bit operations, which take them from the high byte.
    module Arithmetic
      private

      # The eight operations an opcode's bits 5-3 pick: ADD ADC SUB SBC AND
      # XOR OR CP.
      def alu(operation, value)
        case operation
        when 0 then add_a(value, 0)
        when 1 then add_a(value, @f & CF)
        when 2 then @a = subtract(value, 0)
        when 3 then @a = subtract(value, @f & CF)
        when 4 then logic(@a & value, HF)
        when 5 then logic(@a ^ value, 0)
        when 6 then logic(@a | value, 0)
        else compare(value)
        end
      end

      def add_a(value, carry)
        result = @a + value + carry
        assign_flags(SZ53[result & 0xff] | (result >> 8) | ((@a ^ value ^ result) & HF) |
                  (((@a ^ value ^ 0x80) & (@a ^ result) & 0x80) >> 5))
        @a = result & 0xff
      end

      def subtract(value, carry)
        result = @a - value - carry
        assign_flags(SZ53[result & 0xff] | NF | ((result >> 8) & CF) | ((@a ^ value ^ result) & HF) |
                  (((@a ^ value) & (@a ^ result) & 0x80) >> 5))
        result & 0xff
      end

      def compare(value)
        subtract(value, 0)
        assign_flags((@f & ~XYF) | (value & XYF))
      end

      def logic(result, half)
        @a = result
        assign_flags(SZ53P[result] | half)
      end

      def increment(value)
        result = (value + 1) & 0xff
        assign_flags((@f & CF) | SZ53[result] | (result == 0x80 ? PF : 0) | (result.nobits?(0x0f) ? HF : 0))
        result
      end

      def decrement(value)
        result = (value - 1) & 0xff
        assign_flags((@f & CF) | NF | SZ53[result] | (result == 0x7f ? PF : 0) | (value.nobits?(0x0f) ? HF : 0))
        result
      end

      def add16(left, right)
        result = left + right
        @wz = (left + 1) & 0xffff
        assign_flags((@f & (SF | ZF | PF)) | ((result >> 8) & XYF) | (((left ^ right ^ result) >> 8) & HF) |
                  (result >> 16))
        result & 0xffff
      end

      def adc16(right)
        left = hl
        result = left + right + (@f & CF)
        @wz = (left + 1) & 0xffff
        self.hl = result & 0xffff
        assign_flags(word_flags(result) | (((left ^ right ^ result) >> 8) & HF) |
                  (((left ^ right ^ 0x8000) & (left ^ result) & 0x8000) >> 13))
      end

      def sbc16(right)
        left = hl
        result = left - right - (@f & CF)
        @wz = (left + 1) & 0xffff
        self.hl = result & 0xffff
        assign_flags(word_flags(result) | NF | (((left ^ right ^ result) >> 8) & HF) |
                  (((left ^ right) & (left ^ result) & 0x8000) >> 13))
      end

      def word_flags(result)
        ((result >> 8) & (SF | XYF)) | (result.nobits?(0xffff) ? ZF : 0) | ((result >> 16) & CF)
      end

      def daa
        low = @a & 0x0f
        carry = @f.anybits?(CF) || @a > 0x99 ? CF : 0
        correction = (carry.zero? ? 0 : 0x60) | (@f.anybits?(HF) || low > 9 ? 0x06 : 0)
        subtracting = @f.anybits?(NF)
        half = daa_half(low, subtracting)
        @a = (subtracting ? @a - correction : @a + correction) & 0xff
        assign_flags(SZ53P[@a] | (@f & NF) | carry | half)
      end

      def daa_half(low, subtracting)
        if subtracting
          @f.anybits?(HF) && low < 6 ? HF : 0
        else
          low > 9 ? HF : 0
        end
      end

      def neg
        value = @a
        @a = 0
        @a = subtract(value, 0)
      end
    end
  end
end
