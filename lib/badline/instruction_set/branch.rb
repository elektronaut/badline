# frozen_string_literal: true

module Badline
  module InstructionSet
    module Branch
      # Branch if carry clear (C=0).
      #
      # Opcodes:
      #   $90 - relative - 2+ cycles
      def bcc(_addr, _value)
        take_branch unless status.carry?
      end

      # Branch if carry set (C=1).
      #
      # Opcodes:
      #   $B0 - relative - 2+ cycles
      def bcs(_addr, _value)
        take_branch if status.carry?
      end

      # Branch if equal (Z=1).
      #
      # Opcodes:
      #   $F0 - relative - 2+ cycles
      def beq(_addr, _value)
        take_branch if status.zero?
      end

      # Branch if minus (N=1).
      #
      # Opcodes:
      #   $30 - relative - 2+ cycles
      def bmi(_addr, _value)
        take_branch if status.negative?
      end

      # Branch if not equal (Z=0).
      #
      # Opcodes:
      #   $D0 - relative - 2+ cycles
      def bne(_addr, _value)
        take_branch unless status.zero?
      end

      # Branch if plus (N=0).
      #
      # Opcodes:
      #   $10 - relative - 2+ cycles
      def bpl(_addr, _value)
        take_branch unless status.negative?
      end

      # Branch if overflow clear (V=0).
      #
      # Opcodes:
      #   $50 - relative - 2+ cycles
      def bvc(_addr, _value)
        take_branch unless status.overflow?
      end

      # Branch if overflow set (V=1).
      #
      # Opcodes:
      #   $70 - relative - 2+ cycles
      def bvs(_addr, _value)
        take_branch if status.overflow?
      end

      private

      # The sequencer owns the cycles a taken branch costs; the instruction
      # only decides whether it is taken.
      def take_branch
        @branch_taken = true
      end
    end
  end
end
