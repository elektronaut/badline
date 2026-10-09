# frozen_string_literal: true

module Badline
  class Z80
    # Jumps, calls and returns. Each leaves its target in WZ, and JP cc and
    # CALL cc do whether they jump or not.
    module Jumps
      private

      # The conditions bits 5-3 pick: NZ Z NC C PO PE P M.
      def condition?(index)
        case index
        when 0 then @f.nobits?(ZF)
        when 1 then @f.anybits?(ZF)
        when 2 then @f.nobits?(CF)
        when 3 then @f.anybits?(CF)
        when 4 then @f.nobits?(PF)
        when 5 then @f.anybits?(PF)
        when 6 then @f.nobits?(SF)
        else @f.anybits?(SF)
        end
      end

      # NOP, EX AF,AF', DJNZ, JR and JR cc.
      def relative_jump(row)
        case row
        when 0 then nil
        when 1 then exchange_af
        when 2 then decrement_and_jump
        when 3 then jump_relative(fetch_byte)
        else
          offset = fetch_byte
          jump_relative(offset) if condition?(row - 4)
        end
      end

      def decrement_and_jump
        @cycles += 1
        offset = fetch_byte
        @b = (@b - 1) & 0xff
        jump_relative(offset) unless @b.zero?
      end

      def jump_relative(offset)
        @cycles += 5
        @pc = (@pc + offset - (offset > 127 ? 256 : 0)) & 0xffff
        @wz = @pc
      end

      def jump(taken)
        @wz = fetch_word
        @pc = @wz if taken
      end

      def call(taken)
        @wz = fetch_word
        return unless taken

        @cycles += 1
        push(@pc)
        @pc = @wz
      end

      def conditional_return(index)
        @cycles += 1
        return_from_call if condition?(index)
      end

      def return_from_call
        @pc = pop
        @wz = @pc
      end

      def restart(address)
        @cycles += 1
        push(@pc)
        @pc = address
        @wz = address
      end
    end
  end
end
