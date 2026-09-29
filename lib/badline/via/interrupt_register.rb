# frozen_string_literal: true

module Badline
  class VIA
    # The interrupt flag and enable registers. Each source has a flag bit,
    # and IRQ is pulled low while any flag is set with its enable bit.
    class InterruptRegister
      CA2 = 0x01
      CA1 = 0x02
      SR = 0x04
      CB2 = 0x08
      CB1 = 0x10
      TIMER2 = 0x20
      TIMER1 = 0x40

      attr_reader :flags, :enable

      def initialize
        reset!
      end

      def reset!
        @flags = 0x00
        @enable = 0x00
      end

      def save_state(out)
        out.int(@flags).int(@enable)
      end

      def load_state(input)
        @flags = input.int
        @enable = input.int
      end

      def set(bits)
        @flags |= bits
      end

      def clear(bits)
        @flags &= ~bits
      end

      def irq? = @flags.anybits?(@enable)

      # Bit 7 reads the IRQ output.
      def read = irq? ? @flags | 0x80 : @flags

      # Writing 1s clears the flags; bit 7 is ignored.
      def write(value)
        clear(value & 0x7f)
      end

      # Bit 7 reads as 1.
      def read_enable = @enable | 0x80

      # Bit 7 picks between setting and clearing the enable bits given.
      def write_enable(value)
        if value.anybits?(0x80)
          @enable |= value & 0x7f
        else
          @enable &= ~value & 0x7f
        end
      end
    end
  end
end
