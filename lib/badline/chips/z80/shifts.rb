# frozen_string_literal: true

module Badline
  class Z80
    # Rotates, shifts and the bit operations.
    module Shifts
      private

      # RLCA RRCA RLA RRA, which leave S, Z and P/V alone.
      def rotate_a(operation)
        carry = operation.even? ? @a >> 7 : @a & 1
        @a = shifted(operation, @a, carry)
        assign_flags((@f & (SF | ZF | PF)) | (@a & XYF) | carry)
      end

      # The CB page's rotates and shifts by bits 5-3: RLC RRC RL RR SLA SRA
      # SLL SRL. SLL shifts a 1 in.
      def shift(operation, value)
        carry = operation.even? ? value >> 7 : value & 1
        result = shifted(operation, value, carry)
        assign_flags(SZ53P[result] | carry)
        result
      end

      def shifted(operation, value, carry)
        case operation
        when 0 then ((value << 1) | carry) & 0xff
        when 1 then (value >> 1) | (carry << 7)
        when 2 then ((value << 1) | (@f & CF)) & 0xff
        when 3 then (value >> 1) | ((@f & CF) << 7)
        when 4 then (value << 1) & 0xff
        when 5 then (value >> 1) | (value & 0x80)
        when 6 then ((value << 1) | 1) & 0xff
        else value >> 1
        end
      end

      # BIT n tests a bit of +value+ and copies bits 5 and 3 from +source+:
      # the operand for a register, WZ's high byte for a memory operand.
      def bit(number, value, source)
        tested = value & (1 << number)
        flags = (@f & CF) | HF | (source & XYF) | (tested & SF)
        flags |= ZF | PF if tested.zero?
        assign_flags(flags)
      end

      # RRD and RLD rotate a digit through A and (HL).
      def rotate_digits(left)
        address = hl
        value = read_byte(address)
        @cycles += 4
        if left
          write_byte(address, ((value << 4) | (@a & 0x0f)) & 0xff)
          @a = (@a & 0xf0) | (value >> 4)
        else
          write_byte(address, ((@a << 4) | (value >> 4)) & 0xff)
          @a = (@a & 0xf0) | (value & 0x0f)
        end
        @wz = (address + 1) & 0xffff
        assign_flags((@f & CF) | SZ53P[@a])
      end
    end
  end
end
