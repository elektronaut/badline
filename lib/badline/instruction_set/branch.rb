# frozen_string_literal: true

module Badline
  module InstructionSet
    module Branch
      # Branch if carry clear (C=0).
      #
      # Opcodes:
      #   $90 - relative - 2+ cycles
      def bcc(addr, _value)
        branch(addr) unless status.carry?
      end

      # Branch if carry set (C=1).
      #
      # Opcodes:
      #   $B0 - relative - 2+ cycles
      def bcs(addr, _value)
        branch(addr) if status.carry?
      end

      # Branch if equal (Z=1).
      #
      # Opcodes:
      #   $F0 - relative - 2+ cycles
      def beq(addr, _value)
        branch(addr) if status.zero?
      end

      # Branch if minus (N=1).
      #
      # Opcodes:
      #   $30 - relative - 2+ cycles
      def bmi(addr, _value)
        branch(addr) if status.negative?
      end

      # Branch if not equal (Z=0).
      #
      # Opcodes:
      #   $D0 - relative - 2+ cycles
      def bne(addr, _value)
        branch(addr) unless status.zero?
      end

      # Branch if plus (N=0).
      #
      # Opcodes:
      #   $10 - relative - 2+ cycles
      def bpl(addr, _value)
        branch(addr) unless status.negative?
      end

      # Branch if overflow clear (V=0).
      #
      # Opcodes:
      #   $50 - relative - 2+ cycles
      def bvc(addr, _value)
        branch(addr) unless status.overflow?
      end

      # Branch if overflow set (V=1).
      #
      # Opcodes:
      #   $70 - relative - 2+ cycles
      def bvs(addr, _value)
        branch(addr) if status.overflow?
      end

      private

      # A branch within the same page does not re-poll interrupts during
      # its final cycle.
      def branch(addr)
        if high_byte(addr) == high_byte(@program_counter)
          @skip_poll = true
        else
          cycle
        end
        cycle { @program_counter = addr }
      end
    end
  end
end
