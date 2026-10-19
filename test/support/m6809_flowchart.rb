# frozen_string_literal: true

# Where the 6809 vectors and Motorola's documents disagree. MAME made the
# vectors, and on some dead ("Don't Care") cycles it reads another address
# than the MC6809E datasheet's Figure 17 gives. The data a dead cycle
# reads is thrown away, but a read of I/O can have side effects, so the
# core follows the datasheet, and the runner checks those cycles against
# the address each rule below gives. doc/pinned-behaviour.md lists the
# same rules.
module M6809Flowchart
  # A rule: what it follows, the opcodes it covers, and for a case the
  # cycles it moves, as [index, address] pairs.
  Rule = Struct.new(:source, :applies, :cycles)

  READ_MODIFY_WRITE = ((0x00..0x0f).to_a + (0x60..0x7f).to_a).reject { |opcode| [0xd, 0xe].include?(opcode & 0x0f) }
  ARITHMETIC16 = {
    0x00 => [0x83, 0x93, 0xa3, 0xb3, 0x8c, 0x9c, 0xac, 0xbc, 0xc3, 0xd3, 0xe3, 0xf3],
    0x10 => [0x83, 0x93, 0xa3, 0xb3, 0x8c, 0x9c, 0xac, 0xbc, 0xc3, 0xd3, 0xe3, 0xf3],
    0x11 => [0x83, 0x93, 0xa3, 0xb3, 0x8c, 0x9c, 0xac, 0xbc, 0xc3, 0xd3, 0xe3, 0xf3]
  }.freeze
  INDEXED = [0x30, 0x31, 0x32, 0x33, *0x60..0x6f, *(0xa0..0xaf), *(0xe0..0xef)].freeze

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
             ->(test) { [after_postbyte(test, 3)] })
  ].freeze

  # The trace the core should make: each cycle's status, address and
  # data, with the rules' cycles moved and their data left unchecked.
  def expected(test)
    trace = test.cycles.map do |cycle|
      cycle.status == "----" ? ["----", 0, 0] : [cycle.status, cycle.address, cycle.data]
    end
    RULES.each do |rule|
      next unless rule.applies.call(test)

      rule.cycles.call(test).each { |index, address| trace[index] = ["r-m-", address, nil] }
    end
    trace
  end
end
