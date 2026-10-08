# frozen_string_literal: true

module Badline
  class Z80
    # INI, IND, OUTI, OUTD and their repeating forms. B counts the bytes
    # and sets S, Z, 5 and 3. The byte's bit 7 sets N, and adding it to C
    # plus or minus one for INI and IND, or to L for OUTI and OUTD, sets H
    # and C on a carry out and P/V from the parity of its low 3 bits
    # exclusive-ored with B.
    module BlockIO
      private

      def block_input(step, repeat)
        @cycles += 1
        port = bc
        value = input(port)
        @wz = (port + step) & 0xffff
        @b = (@b - 1) & 0xff
        write_byte(hl, value)
        self.hl = (hl + step) & 0xffff
        block_io_flags(value, value + ((@c + step) & 0xff), repeat)
      end

      def block_output(step, repeat)
        @cycles += 1
        value = read_byte(hl)
        @b = (@b - 1) & 0xff
        output(bc, value)
        self.hl = (hl + step) & 0xffff
        @wz = (bc + step) & 0xffff
        block_io_flags(value, value + @l, repeat)
      end

      def block_io_flags(value, sum, repeat)
        carry = sum > 0xff ? HF | CF : 0
        assign_flags(SZ53[@b] | ((value >> 6) & NF) | carry | PARITY[(sum & 7) ^ @b])
        return unless repeat && !@b.zero?

        repeat_block
        repeat_io_flags(value, carry)
      end

      def repeat_io_flags(value, carry)
        flags = @f & ~HF
        if carry.zero?
          flags ^= PARITY[@b & 7] ^ PF
        elsif value.anybits?(0x80)
          flags ^= PARITY[(@b - 1) & 7] ^ PF
          flags |= HF if @b.nobits?(0x0f)
        else
          flags ^= PARITY[(@b + 1) & 7] ^ PF
          flags |= HF if @b.allbits?(0x0f)
        end
        assign_flags(flags)
      end
    end
  end
end
