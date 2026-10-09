# frozen_string_literal: true

module Badline
  class Z80
    # The interrupt mode each of ED 46, 4E, 56, 5E, 66, 6E, 76 and 7E sets.
    # 4E and 6E set mode 0 on the NMOS Z80.
    INTERRUPT_MODES = [0, 0, 1, 2, 0, 0, 1, 2].freeze

    # The ED page: its second quarter, the block instructions, and 8
    # T-states of nothing for the rest.
    module ExtendedPage
      private

      def execute_extended(opcode)
        case opcode >> 6
        when 1 then extended_operation(opcode)
        when 2 then block_operation(opcode) if (opcode & 0x24) == 0x20
        end
      end

      def extended_operation(opcode)
        row = (opcode >> 3) & 7
        case opcode & 7
        when 0 then input_register(row)
        when 1 then output_register(row)
        when 2 then add_pair_with_carry(row)
        when 3 then row.nobits?(1) ? store_word(pair(row >> 1)) : set_pair(row >> 1, load_word)
        when 4 then neg
        when 5 then return_from_interrupt
        when 6 then @im = INTERRUPT_MODES[row]
        else special_register(row)
        end
      end

      # IN r,(C), and IN F,(C) at index 6, which sets the flags alone.
      def input_register(index)
        port = bc
        value = input(port)
        @wz = (port + 1) & 0xffff
        assign_flags((@f & CF) | SZ53P[value])
        set_register(index, value) unless index == 6
      end

      # OUT (C),r, and at index 6 OUT (C),0.
      def output_register(index)
        port = bc
        output(port, index == 6 ? 0 : register(index))
        @wz = (port + 1) & 0xffff
      end

      def add_pair_with_carry(row)
        row.nobits?(1) ? sbc16(pair(row >> 1)) : adc16(pair(row >> 1))
        @cycles += 7
      end

      # RETN and RETI both restore IFF1 from IFF2.
      def return_from_interrupt
        @iff1 = @iff2
        return_from_call
      end

      # LD I,A, LD R,A, LD A,I, LD A,R, RRD and RLD, and two that do
      # nothing.
      def special_register(row)
        case row
        when 0 then @i = load_ir(@a)
        when 1 then @r = load_ir(@a)
        when 2 then @a = load_a_from_ir(@i)
        when 3 then @a = load_a_from_ir(@r)
        when 4 then rotate_digits(false)
        when 5 then rotate_digits(true)
        end
      end

      def load_ir(value)
        @cycles += 1
        value
      end

      # P/V copies IFF2, and an interrupt taken next clears it again.
      def load_a_from_ir(value)
        @cycles += 1
        assign_flags((@f & CF) | SZ53[value] | (@iff2 ? PF : 0))
        @after_ld_a_ir = true
        value
      end
    end
  end
end
