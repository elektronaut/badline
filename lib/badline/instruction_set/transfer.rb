# frozen_string_literal: true

module Badline
  module InstructionSet
    module Transfer
      # +begin_src ruby
      # Load accumulator with memory.
      #
      # Opcodes:
      #   $A1 - indirect_x - 6 cycles
      #   $A5 - zeropage   - 3 cycles
      #   $A9 - immediate  - 2 cycles
      #   $AD - absolute   - 4 cycles
      #   $B1 - indirect_y - 5+ cycles
      #   $B5 - zeropage_x - 4 cycles
      #   $B9 - absolute_y - 4+ cycles
      #   $BD - absolute_x - 4+ cycles
      def lda(_addr, value)
        @a = value
        update_number_flags(@a)
      end

      # Load X register with memory.
      #
      # Opcodes:
      #   $A2 - immediate  - 2 cycles
      #   $A6 - zeropage   - 3 cycles
      #   $AE - absolute   - 4 cycles
      #   $B6 - zeropage_y - 4 cycles
      #   $BE - absolute_y - 4+ cycles
      def ldx(_addr, value)
        @x = value
        update_number_flags(@x)
      end

      # Load Y register with memory.
      #
      # Opcodes:
      #   $A0 - immediate  - 2 cycles
      #   $A4 - zeropage   - 3 cycles
      #   $AC - absolute   - 4 cycles
      #   $B4 - zeropage_x - 4 cycles
      #   $BC - absolute_x - 4+ cycles
      def ldy(_addr, value)
        @y = value
        update_number_flags(@y)
      end

      # Store accumulator in memory.
      #
      # Opcodes:
      #   $81 - indirect_x - 6 cycles
      #   $85 - zeropage   - 3 cycles
      #   $8D - absolute   - 4 cycles
      #   $91 - indirect_y - 6 cycles
      #   $95 - zeropage_x - 4 cycles
      #   $99 - absolute_y - 5 cycles
      #   $9D - absolute_x - 5 cycles
      def sta(addr, _value)
        write_byte(addr, @a)
      end

      # Store X register in memory.
      #
      # Opcodes:
      #   $86 - zeropage   - 3 cycles
      #   $8E - absolute   - 4 cycles
      #   $96 - zeropage_y - 4 cycles
      def stx(addr, _value)
        write_byte(addr, @x)
      end

      # Store Y register in memory.
      #
      # Opcodes:
      #   $84 - zeropage   - 3 cycles
      #   $8C - absolute   - 4 cycles
      #   $94 - zeropage_x - 4 cycles
      def sty(addr, _value)
        write_byte(addr, @y)
      end

      # Transfer accumulator to X register.
      #
      # Opcodes:
      #   $AA - implied - 2 cycles
      def tax(_addr, _value)
        @x = a
        update_number_flags(@x)
      end

      # Transfer accumulator to Y register.
      #
      # Opcodes:
      #   $A8 - implied - 2 cycles
      def tay(_addr, _value)
        @y = a
        update_number_flags(@y)
      end

      # Transfer stack pointer to X register.
      #
      # Opcodes:
      #   $BA - implied - 2 cycles
      def tsx(_addr, _value)
        @x = stack_pointer
        update_number_flags(@x)
      end

      # Transfer X register to accumulator.
      #
      # Opcodes:
      #   $8A - implied - 2 cycles
      def txa(_addr, _operand)
        @a = x
        update_number_flags(@a)
      end

      # Transfer X register to stack pointer.
      #
      # Opcodes:
      #   $9A - implied - 2 cycles
      def txs(_addr, _operand)
        @stack_pointer = x
      end

      # Transfer Y register to accumulator.
      #
      # Opcodes:
      #   $98 - implied - 2 cycles
      def tya(_addr, _operand)
        @a = y
        update_number_flags(@a)
      end
    end
  end
end
