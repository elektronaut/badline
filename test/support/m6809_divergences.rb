# frozen_string_literal: true

# Where the 6809 vectors and the documents disagree, and the core follows
# the documents. MAME made the vectors. On some dead ("Don't Care")
# cycles it reads another address than the MC6809E datasheet's Figure 17
# gives, and some undocumented opcodes act otherwise than David Banks'
# "Undocumented 6809 Behaviours" (github.com/hoglet67/6809Decoder/wiki),
# which was checked on real chips. Each rule below gives what the
# document says for the cases it covers, the runner checks the core
# against that, and doc/pinned-behaviour.md lists the same rules.
module M6809Divergences
  # A rule: the document it follows, the cases it covers, the cycles it
  # moves or adds, as [index, address] pairs whose data isn't checked, and
  # the CC it expects after the case. Either may be nil.
  Rule = Struct.new(:source, :applies, :cycles, :cc)

  NEGATIVE = 0x08
  ZERO = 0x04
  OVERFLOW = 0x02
  CARRY = 0x01

  READ_MODIFY_WRITE = ((0x00..0x0f).to_a + (0x60..0x7f).to_a).reject { |opcode| [0xd, 0xe].include?(opcode & 0x0f) }
  ARITHMETIC16 = {
    0x00 => [0x83, 0x93, 0xa3, 0xb3, 0x8c, 0x9c, 0xac, 0xbc, 0xc3, 0xd3, 0xe3, 0xf3],
    0x10 => [0x83, 0x93, 0xa3, 0xb3, 0x8c, 0x9c, 0xac, 0xbc, 0xc3, 0xd3, 0xe3, 0xf3],
    0x11 => [0x83, 0x93, 0xa3, 0xb3, 0x8c, 0x9c, 0xac, 0xbc, 0xc3, 0xd3, 0xe3, 0xf3]
  }.freeze
  INDEXED = [0x30, 0x31, 0x32, 0x33, *0x60..0x6f, *(0xa0..0xaf), *(0xe0..0xef)].freeze
  STORE_IMMEDIATE = [0x87, 0x8f, 0xc7, 0xcf].freeze
  XADDU = [0xc3, 0xd3, 0xe3, 0xf3].freeze

  module_function

  # The case's prefix ($10, $11 or 0) and opcode.
  def opcode(test)
    first = test.bytes[0]
    [0x10, 0x11].include?(first) ? [first, test.bytes[1]] : [0, first]
  end

  def last(test, back) = test.cycles.length - back

  def subroutine(test) = [[last(test, 4), test.final.registers[:pc]]]

  # The cycle after the postbyte's and the bytes after it, and NNNN plus
  # the bytes up to there.
  def after_postbyte(test, offset)
    prefix, = opcode(test)
    post = prefix.zero? ? 1 : 2
    [post + offset, (test.initial.registers[:pc] + post + offset) & 0xffff]
  end

  def indexed?(test)
    prefix, code = opcode(test)
    INDEXED.include?(code) && (prefix.zero? || code >= 0xa0)
  end

  def postbyte(test) = test.bytes[opcode(test)[0].zero? ? 1 : 2]

  def initial_cc(test) = test.initial.registers[:cc]

  def final_cc(test) = test.final.registers[:cc]

  # CC with N, Z, V and C from +flags+.
  def with_flags(cc, flags) = (cc & 0xf0) | flags

  # X18's CC from the byte after the opcode, read on its second cycle.
  def x18_cc(test)
    masked = initial_cc(test) & test.cycles[1].data
    ((masked << 1) & 0xff) | (masked.nobits?(ZERO) ? 0 : OVERFLOW)
  end

  def daa_cc(test)
    carry = final_cc(test) & CARRY
    sign = test.final.registers[:a] >> 7
    (final_cc(test) & ~OVERFLOW) | (carry == sign ? 0 : OVERFLOW)
  end

  # XADDU's CC: U | $FF00 plus the operand, whose bytes the two cycles
  # before the last read.
  def xaddu_cc(test)
    operand = (test.cycles[-3].data << 8) | test.cycles[-2].data
    left = test.initial.registers[:u] | 0xff00
    sum = left + operand
    result = sum & 0xffff
    flags = (result.anybits?(0x8000) ? NEGATIVE : 0) | (result.zero? ? ZERO : 0) | (sum > 0xffff ? CARRY : 0)
    flags |= OVERFLOW if ((left ^ result) & (operand ^ result)).anybits?(0x8000)
    with_flags(initial_cc(test), flags)
  end

  RULES = [
    Rule.new("Fig. 17 sheet 5, and the DEC extended example: a read-modify-write's dead cycle reads $FFFF",
             ->(test) { opcode(test)[0].zero? && READ_MODIFY_WRITE.include?(opcode(test)[1]) },
             ->(test) { [[last(test, 2), 0xffff]] }),
    Rule.new("Fig. 17 sheet 5: ADDD, SUBD, CMPD, CMPX, CMPY, CMPU and CMPS end on a dead read of $FFFF",
             ->(test) { ARITHMETIC16.fetch(opcode(test)[0]).include?(opcode(test)[1]) },
             ->(test) { [[last(test, 1), 0xffff]] }),
    Rule.new("Fig. 17 sheet 5: JSR's first dead cycle reads the subroutine's address",
             ->(test) { [[0, 0x9d], [0, 0xad], [0, 0xbd]].include?(opcode(test)) },
             ->(test) { subroutine(test) }),
    Rule.new("Fig. 17 sheet 1, and the LBSR example: BSR and LBSR read the subroutine's address",
             ->(test) { [[0, 0x8d], [0, 0x17]].include?(opcode(test)) },
             ->(test) { subroutine(test) }),
    Rule.new("Fig. 17 sheet 2: RTS ends on a dead read of $FFFF",
             ->(test) { opcode(test) == [0, 0x39] },
             ->(test) { [[last(test, 1), 0xffff]] }),
    Rule.new("Fig. 17 sheet 2: TSTA and TSTB read NNNN+1 after the opcode, as the other inherent opcodes do",
             ->(test) { [[0, 0x4d], [0, 0x5d]].include?(opcode(test)) },
             ->(test) { [[1, (test.initial.registers[:pc] + 1) & 0xffff]] }),
    Rule.new("Fig. 17 sheet 4: an 8-bit offset from R is followed by a dead read of $FFFF",
             ->(test) { indexed?(test) && postbyte(test) & 0x8f == 0x88 },
             ->(test) { [[after_postbyte(test, 2)[0], 0xffff]] }),
    Rule.new("Fig. 17 sheet 4: a 16-bit offset from R or PC, D offset and extended indirect read NNNN+4 " \
             "after their offset",
             ->(test) { indexed?(test) && [0x89, 0x8b, 0x8d, 0x8f].include?(postbyte(test) & 0x8f) },
             ->(test) { [after_postbyte(test, 3)] }),
    Rule.new("Banks, X18: 3 cycles, and V = (C & B0) | (Z & B2). The third cycle's address isn't documented; " \
             "the core reads $FFFF",
             ->(test) { opcode(test) == [0, 0x18] },
             ->(_test) { [[2, 0xffff]] },
             ->(test) { x18_cc(test) }),
    Rule.new("Banks, Undefined values of the Overflow Flag: DAA sets V to C xor bit 7 of A",
             ->(test) { opcode(test) == [0, 0x19] },
             nil,
             ->(test) { daa_cc(test) }),
    Rule.new("Banks, XADDU: the operand plus U | $FF00",
             ->(test) { opcode(test)[0] == 0x11 && XADDU.include?(opcode(test)[1]) },
             nil,
             ->(test) { xaddu_cc(test) }),
    Rule.new("Banks, Store Immediate: prefixed, and unprefixed after no instruction (the default group), " \
             "N = 1, Z = 0 and V = 0",
             ->(test) { STORE_IMMEDIATE.include?(opcode(test)[1]) },
             nil,
             ->(test) { (final_cc(test) & ~(NEGATIVE | ZERO | OVERFLOW)) | NEGATIVE })
  ].freeze

  def rules(test) = RULES.select { |rule| rule.applies.call(test) }

  # The trace the core should make: each cycle's status, address and
  # data, with the rules' cycles moved or added and their data left
  # unchecked.
  def expected_trace(test)
    trace = test.cycles.map do |cycle|
      cycle.status == "----" ? ["----", 0, 0] : [cycle.status, cycle.address, cycle.data]
    end
    rules(test).each do |rule|
      rule.cycles&.call(test)&.each { |index, address| trace[index] = ["r-m-", address, nil] }
    end
    trace
  end

  # The registers after the case, with the rules' CC.
  def expected_registers(test)
    registers = test.final.registers.dup
    rules(test).each { |rule| registers[:cc] = rule.cc.call(test) if rule.cc }
    registers
  end
end
