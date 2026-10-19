# frozen_string_literal: true

module Badline
  module Chips
    class M6809
      # The instruction methods the plans' *_exec steps call. A read takes
      # its operand from @value; a write and a read-modify-write leave the
      # byte or word to write there.
      module Operations
        private

        def none; end
        def nop; end
        def sync; end

        def neg = @value = neg8(@value)
        def xnc = @value = xnc8(@value)
        def com = @value = com8(@value)
        def lsr = @value = lsr8(@value)
        def ror = @value = ror8(@value)
        def asr = @value = asr8(@value)
        def asl = @value = asl8(@value)
        def rol = @value = rol8(@value)
        def dec = @value = dec8(@value)
        def xdec = @value = xdec8(@value)
        def inc = @value = inc8(@value)
        def tst = logic8(@value)
        def clr = @value = clr8

        def jmp
          @pc = @ea
        end

        def nega = @a = neg8(@a)
        def xnca = @a = xnc8(@a)
        def coma = @a = com8(@a)
        def lsra = @a = lsr8(@a)
        def rora = @a = ror8(@a)
        def asra = @a = asr8(@a)
        def asla = @a = asl8(@a)
        def rola = @a = rol8(@a)
        def deca = @a = dec8(@a)
        def xdeca = @a = xdec8(@a)
        def inca = @a = inc8(@a)
        def tsta = logic8(@a)
        def xclra = @a = xclr8
        def clra = @a = clr8

        def negb = @b = neg8(@b)
        def xncb = @b = xnc8(@b)
        def comb = @b = com8(@b)
        def lsrb = @b = lsr8(@b)
        def rorb = @b = ror8(@b)
        def asrb = @b = asr8(@b)
        def aslb = @b = asl8(@b)
        def rolb = @b = rol8(@b)
        def decb = @b = dec8(@b)
        def xdecb = @b = xdec8(@b)
        def incb = @b = inc8(@b)
        def tstb = logic8(@b)
        def xclrb = @b = xclr8
        def clrb = @b = clr8

        def suba = @a = sub8(@a, @value, 0)
        def cmpa = sub8(@a, @value, 0)
        def sbca = @a = sub8(@a, @value, carry)
        def anda = @a = logic8(@a & @value)
        def bita = logic8(@a & @value)
        def lda = @a = logic8(@value)
        def sta = @value = logic8(@a)
        def eora = @a = logic8(@a ^ @value)
        def adca = @a = add8(@a, @value, carry)
        def ora = @a = logic8(@a | @value)
        def adda = @a = add8(@a, @value, 0)

        def subb = @b = sub8(@b, @value, 0)
        def cmpb = sub8(@b, @value, 0)
        def sbcb = @b = sub8(@b, @value, carry)
        def andb = @b = logic8(@b & @value)
        def bitb = logic8(@b & @value)
        def ldb = @b = logic8(@value)
        def stb = @value = logic8(@b)
        def eorb = @b = logic8(@b ^ @value)
        def adcb = @b = add8(@b, @value, carry)
        def orb = @b = logic8(@b | @value)
        def addb = @b = add8(@b, @value, 0)

        def subd = self.d = sub16(d, @value)
        def addd = self.d = add16(d, @value)
        def cmpd = sub16(d, @value)
        def cmpx = sub16(@x, @value)
        def cmpy = sub16(@y, @value)
        def cmpu = sub16(@u, @value)
        def cmps = sub16(@s, @value)
        def xaddd = add16(d, @value)
        def xaddu = add16(@u | 0xff00, @value)

        def ldd = self.d = logic16(@value)
        def ldx = @x = logic16(@value)
        def ldy = @y = logic16(@value)
        def ldu = @u = logic16(@value)
        def lds = load_s(logic16(@value))
        def std = @value = logic16(d)
        def stx = @value = logic16(@x)
        def sty = @value = logic16(@y)
        def stu = @value = logic16(@u)
        def sts = @value = logic16(@s)

        # The undocumented stores immediate. Prefixed, they set N and clear
        # Z and V. Unprefixed, their flags hang on the instruction before
        # (Banks' "Flags for unprefixed Store Immediate"), and the 16-bit
        # ones also clear Z unless the register's low byte is 0.
        def xsta = flags(NEGATIVE | ZERO | OVERFLOW, previous_group_flags)
        def xstb = flags(NEGATIVE | ZERO | OVERFLOW, previous_group_flags)
        def xsta2 = flags(NEGATIVE | ZERO | OVERFLOW, NEGATIVE)
        def xstb2 = flags(NEGATIVE | ZERO | OVERFLOW, NEGATIVE)
        def xstx = @value = store_word_low(@x)
        def xstu = @value = store_word_low(@u)

        def xsty = @value = store_word_low_prefixed(@y)
        def xsts = @value = store_word_low_prefixed(@s)
        def xstx2 = @value = store_word_low_prefixed(@x)
        def xstu2 = @value = store_word_low_prefixed(@u)

        def store_word_low(word)
          low = word & 0xff
          set = previous_group_flags & (NEGATIVE | ZERO)
          set &= ~ZERO unless low.zero?
          flags(NEGATIVE | ZERO | OVERFLOW, set)
          low
        end

        def store_word_low_prefixed(word)
          flags(NEGATIVE | ZERO | OVERFLOW, NEGATIVE)
          word & 0xff
        end

        def previous_group_flags
          case @previous_group
          when GROUP_N0_Z1 then ZERO
          when GROUP_A_00 then nz8(@a)
          when GROUP_A_FF then (@a == 0xff ? ZERO : 0) | (@a.anybits?(0x80) ? 0 : NEGATIVE)
          when GROUP_A_01 then decremented_flags(@a)
          when GROUP_B_01 then decremented_flags(@b)
          when GROUP_WORD_01 then decremented_flags(@alu_word >> 8)
          when GROUP_LEA then decremented_flags((@alu_word >> 8) | (@alu_word & 0xff))
          else NEGATIVE
          end
        end

        # Z for 1, N for a negative value less one, V for $80.
        def decremented_flags(value)
          (value == 1 ? ZERO : 0) | ((value - 1).nobits?(0x80) ? 0 : NEGATIVE) | (value == 0x80 ? OVERFLOW : 0)
        end

        # JSR, BSR and LBSR, once the return address is stacked.
        def jsr
          @pc = @ea
        end

        def leax
          @alu_word = @ea
          @x = @ea
          flags(ZERO, @ea.zero? ? ZERO : 0)
        end

        def leay
          @alu_word = @ea
          @y = @ea
          flags(ZERO, @ea.zero? ? ZERO : 0)
        end

        def leas
          @alu_word = @ea
          load_s(@ea)
        end

        def leau
          @alu_word = @ea
          @u = @ea
        end

        def orcc = @cc |= @value
        def andcc = @cc &= @value

        def abx = @x = (@x + @b) & 0xffff

        def mul
          self.d = @a * @b
          flags(ZERO | CARRY, (d.zero? ? ZERO : 0) | (@b >> 7))
        end

        def sex
          @a = @b.nobits?(0x80) ? 0 : 0xff
          flags(NEGATIVE | ZERO, nz16(d))
        end

        # DAA. V is C xor bit 7 of the result, as Banks found, where the
        # datasheet clears it.
        def daa
          correction = 0
          correction |= 0x06 if @cc & HALF_CARRY != 0 || (@a & 0x0f) > 0x09
          high = @a & 0xf0
          correction |= 0x60 if @cc & CARRY != 0 || high > 0x90 || (high > 0x80 && (@a & 0x0f) > 0x09)
          result = (@a + correction) & 0xff
          carry = correction >= 0x60 ? CARRY : 0
          overflow = (carry == 1) == result.anybits?(0x80) ? 0 : OVERFLOW
          flags(NEGATIVE | ZERO | OVERFLOW | CARRY, nz8(result) | overflow | carry)
          @a = result
        end

        # The undocumented $18: each flag, ANDed with its bit of the byte
        # after the opcode, moves one bit up, and V also takes Z ANDed with
        # bit 2.
        def x18
          masked = @cc & @value
          @cc = ((masked << 1) & 0xff) | (masked.nobits?(ZERO) ? 0 : OVERFLOW)
        end

        def exg
          first = @post >> 4
          second = @post & 0x0f
          value = transfer_register(second)
          set_transfer_register(second, sized(transfer_register(first), first, second))
          set_transfer_register(first, sized(value, second, first))
        end

        def tfr
          source = @post >> 4
          destination = @post & 0x0f
          set_transfer_register(destination, sized(transfer_register(source), source, destination))
        end

        # A value moved from register code +from+ to +to+: an 8-bit register
        # fills a 16-bit one's high byte with $FF, and a 16-bit one gives an
        # 8-bit one its low byte.
        def sized(value, from, to)
          return value & 0xff if to >= 8
          return value | 0xff00 if from >= 8

          value
        end

        def swi = software_interrupt(0xfffa, IRQ_MASK | FIRQ_MASK, ENTIRE)
        def swi2 = software_interrupt(0xfff4, 0, ENTIRE)
        def swi3 = software_interrupt(0xfff2, 0, ENTIRE)
        def xres = software_interrupt(0xfffe, 0, 0)
        def xswi2 = software_interrupt(0xfff4, 0, 0)
        def xfirq = software_interrupt(0xfff6, 0, 0)

        def software_interrupt(vector, mask, entire)
          @cc |= entire
          interrupt_vector(vector, mask)
        end
      end
    end
  end
end
