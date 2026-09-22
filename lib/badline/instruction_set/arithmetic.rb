# frozen_string_literal: true

module Badline
  module InstructionSet
    module Arithmetic
      # Add memory with carry to accumulator.
      #
      # Opcodes:
      #   $61 - indirect_x - 6 cycles
      #   $65 - zeropage   - 3 cycles
      #   $69 - immediate  - 2 cycles
      #   $6D - absolute   - 4 cycles
      #   $71 - indirect_y - 5+ cycles
      #   $75 - zeropage_x - 4 cycles
      #   $79 - absolute_y - 4+ cycles
      #   $7D - absolute_x - 4+ cycles
      def adc(_addr, value)
        result = a + value + status.carry
        status.zero = result.nobits?(0xff)

        if status.decimal?
          result = (a & 0x0f) + (value & 0x0f) + status.carry
          result += 0x06 if result > 0x09
          c = result > 0x0f ? 1 : 0
          result = (a & 0xf0) + (value & 0xf0) + (c << 4) + (result & 0x0f)
          update_calculation_flags(value, result)
          result += 0x60 if result > 0x9f
        else
          update_calculation_flags(value, result)
        end

        status.carry = result > 0xff
        @a = result & 0xff
      end

      # Compare memory with accumulator.
      #
      # Opcodes:
      #   $C1 - indirect_x - 6 cycles
      #   $C5 - zeropage   - 3 cycles
      #   $C9 - immediate  - 2 cycles
      #   $CD - absolute   - 4 cycles
      #   $D1 - indirect_y - 5+ cycles
      #   $D5 - zeropage_x - 4 cycles
      #   $D9 - absolute_y - 4+ cycles
      #   $DD - absolute_x - 4+ cycles
      def cmp(_addr, value)
        status.carry = (@a >= value)
        update_number_flags(@a - value)
      end

      # Compare memory with X register.
      #
      # Opcodes:
      #   $E0 - immediate  - 2 cycles
      #   $E4 - zeropage   - 3 cycles
      #   $EC - absolute   - 4 cycles
      def cpx(_addr, value)
        status.carry = @x >= value
        update_number_flags(@x - value)
      end

      # Compare memory with Y register.
      #
      # Opcodes:
      #   $C0 - immediate  - 2 cycles
      #   $C4 - zeropage   - 3 cycles
      #   $CC - absolute   - 4 cycles
      def cpy(_addr, value)
        status.carry = @y >= value
        update_number_flags(@y - value)
      end

      # Subtract memory from accumulator with borrow.
      #
      # Opcodes:
      #   $E1 - indirect_x - 6 cycles
      #   $E5 - zeropage   - 3 cycles
      #   $E9 - immediate  - 2 cycles
      #   $ED - absolute   - 4 cycles
      #   $F1 - indirect_y - 5+ cycles
      #   $F5 - zeropage_x - 4 cycles
      #   $F9 - absolute_y - 4+ cycles
      #   $FD - absolute_x - 4+ cycles
      def sbc(_addr, value)
        inverted = ~value & 0xff
        carry = status.carry? ? 0 : -1

        result = a + inverted + status.carry
        status.zero = result.nobits?(0xff)
        status.carry = result > 0xff
        update_calculation_flags(inverted, result)

        if status.decimal?
          al = (a & 0x0f) - (value & 0x0f) + carry
          al = ((al - 0x06) & 0x0F) - 0x10 if al.negative?

          result = (a & 0xf0) - (value & 0xf0) + al
          result -= 0x60 if result.negative?
        end

        @a = result & 0xff
      end

      private

      def update_calculation_flags(value, result)
        status.negative = result.anybits?(0x80)
        status.overflow = (a ^ value).nobits?(0x80) &&
                          (a ^ result).anybits?(0x80)
      end
    end
  end
end
