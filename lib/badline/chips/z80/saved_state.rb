# frozen_string_literal: true

module Badline
  class Z80
    # The registers, the T-state count and the interrupt latches for a
    # snapshot, taken between instructions.
    module SavedState
      def save_state(out)
        out.marker("Z80")
        out.int(@a).int(@f).int(@b).int(@c).int(@d).int(@e).int(@h).int(@l)
        out.int(@af_alt).int(@bc_alt).int(@de_alt).int(@hl_alt)
        out.int(@i).int(@r).int(@pc).int(@sp).int(@ix).int(@iy).int(@wz).int(@q).int(@last_q).int(@im)
        out.int(@cycles)
        out.boolean(@iff1).boolean(@iff2).boolean(@halted).boolean(@after_ei).boolean(@after_ld_a_ir)
        out.boolean(@int).boolean(@nmi).boolean(@nmi_pending)
      end

      def load_state(input)
        input.marker("Z80")
        load_main_registers(input)
        @af_alt = input.int
        @bc_alt = input.int
        @de_alt = input.int
        @hl_alt = input.int
        load_special_registers(input)
        @cycles = input.int
        load_latches(input)
        @prefix = 0
      end

      private

      def load_main_registers(input)
        @a = input.int
        @f = input.int
        @b = input.int
        @c = input.int
        @d = input.int
        @e = input.int
        @h = input.int
        @l = input.int
      end

      def load_special_registers(input)
        @i = input.int
        @r = input.int
        @pc = input.int
        @sp = input.int
        @ix = input.int
        @iy = input.int
        @wz = input.int
        @q = input.int
        @last_q = input.int
        @im = input.int
      end

      def load_latches(input)
        @iff1 = input.boolean?
        @iff2 = input.boolean?
        @halted = input.boolean?
        @after_ei = input.boolean?
        @after_ld_a_ir = input.boolean?
        @int = input.boolean?
        @nmi = input.boolean?
        @nmi_pending = input.boolean?
      end
    end
  end
end
