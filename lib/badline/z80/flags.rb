# frozen_string_literal: true

module Badline
  class Z80
    CF = 0x01
    NF = 0x02
    PF = 0x04
    XF = 0x08
    HF = 0x10
    YF = 0x20
    ZF = 0x40
    SF = 0x80

    # Bits 5 and 3, which most instructions copy from a result.
    XYF = YF | XF

    # S, Z, Y and X as a result byte sets them.
    SZ53 = Array.new(256) { |v| (v & (SF | XYF)) | (v.zero? ? ZF : 0) }.freeze

    # P/V as parity: set when a byte has an even number of bits set.
    PARITY = Array.new(256) { |v| (0x6996 >> ((v ^ (v >> 4)) & 0x0f)).nobits?(1) ? PF : 0 }.freeze

    SZ53P = Array.new(256) { |v| SZ53[v] | PARITY[v] }.freeze

    # The flags, which the core keeps in F as the chip does. Every
    # instruction that sets them through the ALU also latches them in Q,
    # which SCF and CCF read on the next instruction.
    module Flags
      private

      def assign_flags(value)
        @f = value
        @q = value
      end
    end
  end
end
