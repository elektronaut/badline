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
        def xaddu = add16(@u, @value)

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

        # The undocumented stores immediate.
        def xsta = logic8(@a)
        def xstb = logic8(@b)
        def xsta2 = logic8(@a)
        def xstb2 = logic8(@b)
        def xstx = @value = logic16(@x) & 0xff
        def xstu = @value = logic16(@u) & 0xff
        def xsty = @value = logic16(@y) & 0xff
        def xsts = @value = logic16(@s) & 0xff
        def xstx2 = @value = logic16(@x) & 0xff
        def xstu2 = @value = logic16(@u) & 0xff

        # JSR, BSR and LBSR, once the return address is stacked.
        def jsr
          @pc = @ea
        end

        def leax
          @x = @ea
          flags(ZERO, @ea.zero? ? ZERO : 0)
        end

        def leay
          @y = @ea
          flags(ZERO, @ea.zero? ? ZERO : 0)
        end

        def leas = load_s(@ea)
        def leau = @u = @ea

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

        def daa
          correction = 0
          correction |= 0x06 if @cc & HALF_CARRY != 0 || (@a & 0x0f) > 0x09
          high = @a & 0xf0
          correction |= 0x60 if @cc & CARRY != 0 || high > 0x90 || (high > 0x80 && (@a & 0x0f) > 0x09)
          result = (@a + correction) & 0xff
          flags(NEGATIVE | ZERO | OVERFLOW | CARRY, nz8(result) | (correction >= 0x60 ? CARRY : 0))
          @a = result
        end

        # The undocumented $18: each flag, ANDed with its bit of the byte
        # after the opcode, moves one bit up, and V also takes Z.
        def x18
          @cc = (((@cc & @value) << 1) & 0xff) | (@cc.nobits?(ZERO) ? 0 : OVERFLOW)
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
