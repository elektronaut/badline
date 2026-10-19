# frozen_string_literal: true

module Badline
  module Chips
    class M6809
      # The ALU: each method returns its result and sets the flags it
      # changes.
      module Arithmetic
        private

        def flags(clear, set)
          @cc = (@cc & ~clear & 0xff) | set
        end

        def nz8(result) = (result.nobits?(0x80) ? 0 : NEGATIVE) | (result.zero? ? ZERO : 0)

        def nz16(result) = (result.nobits?(0x8000) ? 0 : NEGATIVE) | (result.zero? ? ZERO : 0)

        # Loads, stores, AND, OR, EOR and TST: N and Z, V cleared.
        def logic8(result)
          flags(NEGATIVE | ZERO | OVERFLOW, nz8(result))
          result
        end

        def logic16(result)
          flags(NEGATIVE | ZERO | OVERFLOW, nz16(result))
          result
        end

        def add8(left, right, carry)
          sum = left + right + carry
          result = sum & 0xff
          overflow = ((left ^ result) & (right ^ result)).nobits?(0x80) ? 0 : OVERFLOW
          half = (left ^ right ^ sum).nobits?(0x10) ? 0 : HALF_CARRY
          flags(HALF_CARRY | NEGATIVE | ZERO | OVERFLOW | CARRY,
                half | nz8(result) | overflow | (sum > 0xff ? CARRY : 0))
          result
        end

        def sub8(left, right, borrow)
          difference = left - right - borrow
          result = difference & 0xff
          overflow = ((left ^ right) & (left ^ result)).nobits?(0x80) ? 0 : OVERFLOW
          flags(NEGATIVE | ZERO | OVERFLOW | CARRY, nz8(result) | overflow | (difference.negative? ? CARRY : 0))
          result
        end

        def add16(left, right)
          sum = left + right
          result = sum & 0xffff
          @alu_word = result
          overflow = ((left ^ result) & (right ^ result)).nobits?(0x8000) ? 0 : OVERFLOW
          flags(NEGATIVE | ZERO | OVERFLOW | CARRY, nz16(result) | overflow | (sum > 0xffff ? CARRY : 0))
          result
        end

        def sub16(left, right)
          difference = left - right
          result = difference & 0xffff
          @alu_word = result
          overflow = ((left ^ right) & (left ^ result)).nobits?(0x8000) ? 0 : OVERFLOW
          flags(NEGATIVE | ZERO | OVERFLOW | CARRY, nz16(result) | overflow | (difference.negative? ? CARRY : 0))
          result
        end

        def carry = @cc & CARRY

        def neg8(value) = sub8(0, value, 0)

        def com8(value)
          result = ~value & 0xff
          flags(NEGATIVE | ZERO | OVERFLOW | CARRY, nz8(result) | CARRY)
          result
        end

        # The undocumented XNC: NEG with C clear, COM with C set.
        def xnc8(value) = carry.zero? ? neg8(value) : com8(value)

        def lsr8(value)
          result = value >> 1
          flags(NEGATIVE | ZERO | CARRY, nz8(result) | (value & 1))
          result
        end

        def ror8(value)
          result = (value >> 1) | (carry << 7)
          flags(NEGATIVE | ZERO | CARRY, nz8(result) | (value & 1))
          result
        end

        def asr8(value)
          result = (value >> 1) | (value & 0x80)
          flags(NEGATIVE | ZERO | CARRY, nz8(result) | (value & 1))
          result
        end

        def asl8(value) = rotate_left8(value, 0)

        def rol8(value) = rotate_left8(value, carry)

        def rotate_left8(value, low)
          result = ((value << 1) | low) & 0xff
          overflow = (value ^ (value << 1)).nobits?(0x80) ? 0 : OVERFLOW
          flags(NEGATIVE | ZERO | OVERFLOW | CARRY, nz8(result) | overflow | (value >> 7))
          result
        end

        def dec8(value)
          result = (value - 1) & 0xff
          flags(NEGATIVE | ZERO | OVERFLOW, nz8(result) | (value == 0x80 ? OVERFLOW : 0))
          result
        end

        # The undocumented XDEC: DEC, with C set unless the operand was 0.
        def xdec8(value)
          result = dec8(value)
          flags(CARRY, value.zero? ? 0 : CARRY)
          result
        end

        def inc8(value)
          result = (value + 1) & 0xff
          flags(NEGATIVE | ZERO | OVERFLOW, nz8(result) | (value == 0x7f ? OVERFLOW : 0))
          result
        end

        def clr8
          flags(NEGATIVE | ZERO | OVERFLOW | CARRY, ZERO)
          0
        end

        # The undocumented XCLRA and XCLRB: CLR, but C stays.
        def xclr8
          flags(NEGATIVE | ZERO | OVERFLOW, ZERO)
          0
        end
      end
    end
  end
end
