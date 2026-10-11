# frozen_string_literal: true

module Badline
  class Z80
    # EX AF,AF', EXX, EX DE,HL and EX (SP),HL. Only the last swaps IX or IY
    # after a prefix.
    module Exchanges
      private

      def exchange_alternates
        bc_alt = @bc_alt
        de_alt = @de_alt
        hl_alt = @hl_alt
        @bc_alt = bc
        @de_alt = de
        @hl_alt = hl
        self.bc = bc_alt
        self.de = de_alt
        self.hl = hl_alt
      end

      def exchange_af
        af_alt = @af_alt
        @af_alt = af
        self.af = af_alt
      end

      def exchange_de_hl
        d = @d
        e = @e
        @d = @h
        @e = @l
        @h = d
        @l = e
      end

      def exchange_stack_top
        low = read_byte(@sp)
        high = read_byte((@sp + 1) & 0xffff)
        @cycles += 1
        value = hl_or_index
        write_byte((@sp + 1) & 0xffff, value >> 8)
        write_byte(@sp, value & 0xff)
        @cycles += 2
        @wz = low | (high << 8)
        self.hl_or_index = @wz
      end
    end
  end
end
