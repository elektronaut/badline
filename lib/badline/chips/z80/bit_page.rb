# frozen_string_literal: true

module Badline
  class Z80
    # The CB page: rotates and shifts (quarter 0), BIT (1), RES (2) and SET
    # (3) of the bit the row names, on the column's register or (HL). After
    # DD or FD the operand is always (IX+d): the displacement comes before
    # the opcode, and an opcode that names a register other than (HL) also
    # copies the result into it.
    module BitPage
      private

      def execute_bits(opcode)
        operation = opcode >> 6
        number = (opcode >> 3) & 7
        index = opcode & 7
        return bits_in_memory(operation, number, hl) if index == 6

        value = register(index)
        if operation == 1
          bit(number, value, value)
        else
          set_register(index, bit_result(operation, number, value))
        end
      end

      def execute_index_bits
        displaced
        opcode = fetch_byte
        @cycles += 2
        result = bits_in_memory(opcode >> 6, (opcode >> 3) & 7, @wz)
        index = opcode & 7
        set_plain_register(index, result) unless index == 6 || (opcode >> 6) == 1
      end

      def bits_in_memory(operation, number, address)
        value = read_byte(address)
        @cycles += 1
        return bit(number, value, @wz >> 8) if operation == 1

        result = bit_result(operation, number, value)
        write_byte(address, result)
        result
      end

      def bit_result(operation, number, value)
        case operation
        when 0 then shift(number, value)
        when 2 then value & ~(1 << number) & 0xff
        else value | (1 << number)
        end
      end
    end
  end
end
