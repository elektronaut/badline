# frozen_string_literal: true

module Badline
  module Chips
    class Z80
      # The Z80's fields in a keyed snapshot module (Snapshot::Keyed),
      # between instructions, where it always is after the C128's cycle:
      # the registers, the T-state count and the interrupt latches.
      module KeyedState
        def save_fields(out)
          out.int("a", @a).int("f", @f).int("b", @b).int("c", @c).int("d", @d).int("e", @e).int("h", @h).int("l", @l)
          out.int("af_alt", @af_alt).int("bc_alt", @bc_alt).int("de_alt", @de_alt).int("hl_alt", @hl_alt)
          out.int("i", @i).int("r", @r).int("pc", @pc).int("sp", @sp).int("ix", @ix).int("iy", @iy).int("wz", @wz)
          out.int("q", @q).int("last_q", @last_q).int("im", @im).int("cycles", @cycles)
          out.bool("iff1", @iff1).bool("iff2", @iff2).bool("halted", @halted).bool("after_ei", @after_ei)
          out.bool("after_ld_a_ir", @after_ld_a_ir).bool("int", @int).bool("nmi", @nmi)
          out.bool("nmi_pending", @nmi_pending)
        end

        def load_fields(input)
          load_main_fields(input)
          load_special_fields(input)
          @cycles = input.int("cycles", @cycles)
          load_latch_fields(input)
          @prefix = 0
        end

        def restored! = nil

        private

        def load_main_fields(input)
          @a = input.byte("a", @a)
          @f = input.byte("f", @f)
          @b = input.byte("b", @b)
          @c = input.byte("c", @c)
          @d = input.byte("d", @d)
          @e = input.byte("e", @e)
          @h = input.byte("h", @h)
          @l = input.byte("l", @l)
          @af_alt = input.word("af_alt", @af_alt)
          @bc_alt = input.word("bc_alt", @bc_alt)
          @de_alt = input.word("de_alt", @de_alt)
          @hl_alt = input.word("hl_alt", @hl_alt)
        end

        def load_special_fields(input)
          @i = input.byte("i", @i)
          @r = input.byte("r", @r)
          @pc = input.word("pc", @pc)
          @sp = input.word("sp", @sp)
          @ix = input.word("ix", @ix)
          @iy = input.word("iy", @iy)
          @wz = input.word("wz", @wz)
          @q = input.byte("q", @q)
          @last_q = input.byte("last_q", @last_q)
          @im = input.int("im", @im)
        end

        def load_latch_fields(input)
          @iff1 = input.bool("iff1", @iff1)
          @iff2 = input.bool("iff2", @iff2)
          @halted = input.bool("halted", @halted)
          @after_ei = input.bool("after_ei", @after_ei)
          @after_ld_a_ir = input.bool("after_ld_a_ir", @after_ld_a_ir)
          @int = input.bool("int", @int)
          @nmi = input.bool("nmi", @nmi)
          @nmi_pending = input.bool("nmi_pending", @nmi_pending)
        end
      end
    end
  end
end
