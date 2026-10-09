# frozen_string_literal: true

module Badline
  class Z80
    # The register file. Opcodes name 8-bit registers by a 3-bit index,
    # B C D E H L (HL) A, and pairs by a 2-bit one, BC DE HL SP, or BC DE
    # HL AF for PUSH and POP. After a DD or FD prefix, HL means IX or IY
    # and H and L their halves, except beside an (IX+d) operand.
    module Registers
      attr_accessor :a, :f, :b, :c, :d, :e, :h, :l, :i, :r, :pc, :sp, :ix, :iy, :wz, :im, :q,
                    :af_alt, :bc_alt, :de_alt, :hl_alt, :iff1, :iff2, :halted, :after_ei, :after_ld_a_ir

      def af = (@a << 8) | @f
      def bc = (@b << 8) | @c
      def de = (@d << 8) | @e
      def hl = (@h << 8) | @l

      def af=(value)
        @a = value >> 8
        @f = value & 0xff
      end

      def bc=(value)
        @b = value >> 8
        @c = value & 0xff
      end

      def de=(value)
        @d = value >> 8
        @e = value & 0xff
      end

      def hl=(value)
        @h = value >> 8
        @l = value & 0xff
      end

      private

      def register(index)
        case index
        when 0 then @b
        when 1 then @c
        when 2 then @d
        when 3 then @e
        when 4 then @prefix.zero? ? @h : index_register >> 8
        when 5 then @prefix.zero? ? @l : index_register & 0xff
        else @a
        end
      end

      def set_register(index, value)
        case index
        when 0 then @b = value
        when 1 then @c = value
        when 2 then @d = value
        when 3 then @e = value
        when 4 then @prefix.zero? ? @h = value : self.index_register = (index_register & 0xff) | (value << 8)
        when 5 then @prefix.zero? ? @l = value : self.index_register = (index_register & 0xff00) | value
        else @a = value
        end
      end

      # The register an (HL) or (IX+d) operand sits beside: H and L are
      # always themselves.
      def plain_register(index)
        case index
        when 4 then @h
        when 5 then @l
        else register(index)
        end
      end

      def set_plain_register(index, value)
        case index
        when 4 then @h = value
        when 5 then @l = value
        else set_register(index, value)
        end
      end

      def pair(index)
        case index
        when 0 then bc
        when 1 then de
        when 2 then hl_or_index
        else @sp
        end
      end

      def set_pair(index, value)
        case index
        when 0 then self.bc = value
        when 1 then self.de = value
        when 2 then self.hl_or_index = value
        else @sp = value
        end
      end

      # The pairs PUSH and POP name, with AF in place of SP.
      def stack_pair(index) = index == 3 ? af : pair(index)

      def set_stack_pair(index, value)
        index == 3 ? self.af = value : set_pair(index, value)
      end

      def hl_or_index = @prefix.zero? ? hl : index_register

      def hl_or_index=(value)
        @prefix.zero? ? self.hl = value : self.index_register = value
      end

      def index_register = @prefix == 1 ? @ix : @iy

      def index_register=(value)
        @prefix == 1 ? @ix = value : @iy = value
      end
    end
  end
end
