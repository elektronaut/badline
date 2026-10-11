# frozen_string_literal: true

module Badline
  module InstructionSet
    module Bitwise
      # Performs bitwise AND on accumulator with memory.
      #
      # Opcodes:
      #   $21 - indirect_x - 6 cycles
      #   $25 - zeropage   - 3 cycles
      #   $29 - immediate  - 2 cycles
      #   $2D - absolute   - 4 cycles
      #   $31 - indirect_y - 5+ cycles
      #   $35 - zeropage_x - 4 cycles
      #   $39 - absolute_y - 4+ cycles
      #   $3D - absolute_x - 4+ cycles
      def and(_addr, value)
        @a &= value
        update_number_flags(@a)
      end

      # Arithmetic shift left. Shifts bits left by one position.
      #
      # Opcodes:
      #   $06 - zeropage   - 5 cycles
      #   $0A - accumulator- 2 cycles
      #   $0E - absolute   - 6 cycles
      #   $16 - zeropage_x - 6 cycles
      #   $1E - absolute_x - 7 cycles
      def asl(addr, value)
        result = (value << 1) & 0xff
        status.carry = value[7]
        write_modified(addr, result)
        update_number_flags(result)
      end

      # Tests bits in memory with accumulator.
      #
      # Opcodes:
      #   $24 - zeropage - 3 cycles
      #   $2C - absolute - 4 cycles
      def bit(_addr, value)
        status.value = ((status.value & 0b00111111) +
                        (value & 0b11000000)).to_i
        status.zero = (a & value).nobits?(0xff)
      end

      # Performs bitwise XOR on accumulator with memory.
      #
      # Opcodes:
      #   $41 - indirect_x - 6 cycles
      #   $45 - zeropage   - 3 cycles
      #   $49 - immediate  - 2 cycles
      #   $4D - absolute   - 4 cycles
      #   $51 - indirect_y - 5+ cycles
      #   $55 - zeropage_x - 4 cycles
      #   $59 - absolute_y - 4+ cycles
      #   $5D - absolute_x - 4+ cycles
      def eor(_addr, value)
        @a = (@a ^ value) & 0xff
        update_number_flags(@a)
      end

      # Logical shift right. Shifts bits right by one position.
      #
      # Opcodes:
      #   $46 - zeropage   - 5 cycles
      #   $4A - accumulator- 2 cycles
      #   $4E - absolute   - 6 cycles
      #   $56 - zeropage_x - 6 cycles
      #   $5E - absolute_x - 7 cycles
      def lsr(addr, value)
        result = (value >> 1) & 0xff
        status.carry = value[0]
        write_modified(addr, result)
        update_number_flags(result)
      end

      # Performs bitwise OR on accumulator with memory.
      #
      # Opcodes:
      #   $01 - indirect_x - 6 cycles
      #   $05 - zeropage   - 3 cycles
      #   $09 - immediate  - 2 cycles
      #   $0D - absolute   - 4 cycles
      #   $11 - indirect_y - 5+ cycles
      #   $15 - zeropage_x - 4 cycles
      #   $19 - absolute_y - 4+ cycles
      #   $1D - absolute_x - 4+ cycles
      def ora(_addr, value)
        @a |= value
        update_number_flags(@a)
      end

      # Rotate left through carry.
      #
      # Opcodes:
      #   $26 - zeropage   - 5 cycles
      #   $2A - accumulator- 2 cycles
      #   $2E - absolute   - 6 cycles
      #   $36 - zeropage_x - 6 cycles
      #   $3E - absolute_x - 7 cycles
      def rol(addr, value)
        result = ((value << 1) + status.carry) & 0xff
        status.carry = value[7]
        write_modified(addr, result)
        update_number_flags(result)
      end

      # Rotate right through carry.
      #
      # Opcodes:
      #   $66 - zeropage   - 5 cycles
      #   $6A - accumulator- 2 cycles
      #   $6E - absolute   - 6 cycles
      #   $76 - zeropage_x - 6 cycles
      #   $7E - absolute_x - 7 cycles
      def ror(addr, value)
        result = ((value >> 1) + (status.carry? ? 0x80 : 0)) & 0xff
        status.carry = value[0]
        write_modified(addr, result)
        update_number_flags(result)
      end
    end
  end
end
