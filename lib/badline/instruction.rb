# frozen_string_literal: true

module Badline
  class Instruction
    OPERAND_LENGTHS = {
      implied: 0, accumulator: 0,
      immediate: 1, relative: 1, zeropage: 1, zeropage_x: 1, zeropage_y: 1,
      indirect_x: 1, indirect_y: 1,
      absolute: 2, absolute_x: 2, absolute_y: 2, indirect: 2
    }.freeze

    attr_reader :name, :addressing_mode, :operand_length

    def initialize(name, addressing_mode,
                   illegal: false, boundary_cycle: false)
      @name = name
      @addressing_mode = addressing_mode
      @boundary_cycle = boundary_cycle
      @illegal = illegal
      @operand_length = OPERAND_LENGTHS[addressing_mode]
    end

    def boundary_cycle?
      @boundary_cycle
    end

    def illegal?
      @illegal
    end

    def length
      1 + operand_length
    end

    def operand?
      operand_length.positive?
    end

    # Opcode table, keyed by opcode. Built once at load time rather than
    # memoized on first use: a lazily built table is rebuilt on every lookup
    # under Spinel, and this sits in the CPU's hot path.
    MAP = {
      0x00 => Instruction.new(:brk, :implied),
      0x01 => Instruction.new(:ora, :indirect_x),
      0x02 => Instruction.new(:jam, :implied, illegal: true),
      0x03 => Instruction.new(:slo, :indirect_x, illegal: true),
      0x04 => Instruction.new(:nop, :zeropage, illegal: true),
      0x05 => Instruction.new(:ora, :zeropage),
      0x06 => Instruction.new(:asl, :zeropage),
      0x07 => Instruction.new(:slo, :zeropage, illegal: true),
      0x08 => Instruction.new(:php, :implied),
      0x09 => Instruction.new(:ora, :immediate),
      0x0a => Instruction.new(:asl, :accumulator),
      0x0b => Instruction.new(:anc, :immediate, illegal: true),
      0x0c => Instruction.new(:nop, :absolute, illegal: true),
      0x0d => Instruction.new(:ora, :absolute),
      0x0e => Instruction.new(:asl, :absolute),
      0x0f => Instruction.new(:slo, :absolute, illegal: true),

      0x10 => Instruction.new(:bpl, :relative),
      0x11 => Instruction.new(:ora, :indirect_y, boundary_cycle: true),
      0x12 => Instruction.new(:jam, :implied, illegal: true),
      0x13 => Instruction.new(:slo, :indirect_y, illegal: true),
      0x14 => Instruction.new(:nop, :zeropage_x, illegal: true),
      0x15 => Instruction.new(:ora, :zeropage_x),
      0x16 => Instruction.new(:asl, :zeropage_x),
      0x17 => Instruction.new(:slo, :zeropage_x, illegal: true),
      0x18 => Instruction.new(:clc, :implied),
      0x19 => Instruction.new(:ora, :absolute_y, boundary_cycle: true),
      0x1a => Instruction.new(:nop, :implied, illegal: true),
      0x1b => Instruction.new(:slo, :absolute_y, illegal: true),
      0x1c => Instruction.new(:nop, :absolute_x, boundary_cycle: true, illegal: true),
      0x1d => Instruction.new(:ora, :absolute_x, boundary_cycle: true),
      0x1e => Instruction.new(:asl, :absolute_x),
      0x1f => Instruction.new(:slo, :absolute_x, illegal: true),

      0x20 => Instruction.new(:jsr, :absolute),
      0x21 => Instruction.new(:and, :indirect_x),
      0x22 => Instruction.new(:jam, :implied, illegal: true),
      0x23 => Instruction.new(:rla, :indirect_x, illegal: true),
      0x24 => Instruction.new(:bit, :zeropage),
      0x25 => Instruction.new(:and, :zeropage),
      0x26 => Instruction.new(:rol, :zeropage),
      0x27 => Instruction.new(:rla, :zeropage, illegal: true),
      0x28 => Instruction.new(:plp, :implied),
      0x29 => Instruction.new(:and, :immediate),
      0x2a => Instruction.new(:rol, :accumulator),
      0x2b => Instruction.new(:anc, :immediate, illegal: true),
      0x2c => Instruction.new(:bit, :absolute),
      0x2d => Instruction.new(:and, :absolute),
      0x2e => Instruction.new(:rol, :absolute),
      0x2f => Instruction.new(:rla, :absolute, illegal: true),

      0x30 => Instruction.new(:bmi, :relative),
      0x31 => Instruction.new(:and, :indirect_y, boundary_cycle: true),
      0x32 => Instruction.new(:jam, :implied, illegal: true),
      0x33 => Instruction.new(:rla, :indirect_y, illegal: true),
      0x34 => Instruction.new(:nop, :zeropage_x, illegal: true),
      0x35 => Instruction.new(:and, :zeropage_x),
      0x36 => Instruction.new(:rol, :zeropage_x),
      0x37 => Instruction.new(:rla, :zeropage_x, illegal: true),
      0x38 => Instruction.new(:sec, :implied),
      0x39 => Instruction.new(:and, :absolute_y, boundary_cycle: true),
      0x3a => Instruction.new(:nop, :implied, illegal: true),
      0x3b => Instruction.new(:rla, :absolute_y, illegal: true),
      0x3c => Instruction.new(:nop, :absolute_x, boundary_cycle: true, illegal: true),
      0x3d => Instruction.new(:and, :absolute_x, boundary_cycle: true),
      0x3e => Instruction.new(:rol, :absolute_x),
      0x3f => Instruction.new(:rla, :absolute_x, illegal: true),

      0x40 => Instruction.new(:rti, :implied),
      0x41 => Instruction.new(:eor, :indirect_x),
      0x42 => Instruction.new(:jam, :implied, illegal: true),
      0x43 => Instruction.new(:sre, :indirect_x, illegal: true),
      0x44 => Instruction.new(:nop, :zeropage, illegal: true),
      0x45 => Instruction.new(:eor, :zeropage),
      0x46 => Instruction.new(:lsr, :zeropage),
      0x47 => Instruction.new(:sre, :zeropage, illegal: true),
      0x48 => Instruction.new(:pha, :implied),
      0x49 => Instruction.new(:eor, :immediate),
      0x4a => Instruction.new(:lsr, :accumulator),
      0x4b => Instruction.new(:alr, :immediate, illegal: true),
      0x4c => Instruction.new(:jmp, :absolute),
      0x4d => Instruction.new(:eor, :absolute),
      0x4e => Instruction.new(:lsr, :absolute),
      0x4f => Instruction.new(:sre, :absolute, illegal: true),

      0x50 => Instruction.new(:bvc, :relative),
      0x51 => Instruction.new(:eor, :indirect_y, boundary_cycle: true),
      0x52 => Instruction.new(:jam, :implied, illegal: true),
      0x53 => Instruction.new(:sre, :indirect_y, illegal: true),
      0x54 => Instruction.new(:nop, :zeropage_x, illegal: true),
      0x55 => Instruction.new(:eor, :zeropage_x),
      0x56 => Instruction.new(:lsr, :zeropage_x),
      0x57 => Instruction.new(:sre, :zeropage_x, illegal: true),
      0x58 => Instruction.new(:cli, :implied),
      0x59 => Instruction.new(:eor, :absolute_y, boundary_cycle: true),
      0x5a => Instruction.new(:nop, :implied, illegal: true),
      0x5b => Instruction.new(:sre, :absolute_y, illegal: true),
      0x5c => Instruction.new(:nop, :absolute_x, boundary_cycle: true, illegal: true),
      0x5d => Instruction.new(:eor, :absolute_x, boundary_cycle: true),
      0x5e => Instruction.new(:lsr, :absolute_x),
      0x5f => Instruction.new(:sre, :absolute_x, illegal: true),

      0x60 => Instruction.new(:rts, :implied),
      0x61 => Instruction.new(:adc, :indirect_x),
      0x62 => Instruction.new(:jam, :implied, illegal: true),
      0x63 => Instruction.new(:rra, :indirect_x, illegal: true),
      0x64 => Instruction.new(:nop, :zeropage, illegal: true),
      0x65 => Instruction.new(:adc, :zeropage),
      0x66 => Instruction.new(:ror, :zeropage),
      0x67 => Instruction.new(:rra, :zeropage, illegal: true),
      0x68 => Instruction.new(:pla, :implied),
      0x69 => Instruction.new(:adc, :immediate),
      0x6a => Instruction.new(:ror, :accumulator),
      0x6b => Instruction.new(:arr, :immediate, illegal: true),
      0x6c => Instruction.new(:jmp, :indirect),
      0x6d => Instruction.new(:adc, :absolute),
      0x6e => Instruction.new(:ror, :absolute),
      0x6f => Instruction.new(:rra, :absolute, illegal: true),

      0x70 => Instruction.new(:bvs, :relative),
      0x71 => Instruction.new(:adc, :indirect_y, boundary_cycle: true),
      0x72 => Instruction.new(:jam, :implied, illegal: true),
      0x73 => Instruction.new(:rra, :indirect_y, illegal: true),
      0x74 => Instruction.new(:nop, :zeropage_x, illegal: true),
      0x75 => Instruction.new(:adc, :zeropage_x),
      0x76 => Instruction.new(:ror, :zeropage_x),
      0x77 => Instruction.new(:rra, :zeropage_x, illegal: true),
      0x78 => Instruction.new(:sei, :implied),
      0x79 => Instruction.new(:adc, :absolute_y, boundary_cycle: true),
      0x7a => Instruction.new(:nop, :implied, illegal: true),
      0x7b => Instruction.new(:rra, :absolute_y, illegal: true),
      0x7c => Instruction.new(:nop, :absolute_x, boundary_cycle: true, illegal: true),
      0x7d => Instruction.new(:adc, :absolute_x, boundary_cycle: true),
      0x7e => Instruction.new(:ror, :absolute_x),
      0x7f => Instruction.new(:rra, :absolute_x, illegal: true),

      0x80 => Instruction.new(:nop_nocycle, :immediate, illegal: true),
      0x81 => Instruction.new(:sta, :indirect_x),
      0x82 => Instruction.new(:nop_nocycle, :immediate, illegal: true),
      0x83 => Instruction.new(:sax, :indirect_x, illegal: true),
      0x84 => Instruction.new(:sty, :zeropage),
      0x85 => Instruction.new(:sta, :zeropage),
      0x86 => Instruction.new(:stx, :zeropage),
      0x87 => Instruction.new(:sax, :zeropage, illegal: true),
      0x88 => Instruction.new(:dey, :implied),
      0x89 => Instruction.new(:nop_nocycle, :immediate, illegal: true),
      0x8a => Instruction.new(:txa, :implied),
      0x8b => Instruction.new(:ane, :immediate, illegal: true),
      0x8c => Instruction.new(:sty, :absolute),
      0x8d => Instruction.new(:sta, :absolute),
      0x8e => Instruction.new(:stx, :absolute),
      0x8f => Instruction.new(:sax, :absolute, illegal: true),

      0x90 => Instruction.new(:bcc, :relative),
      0x91 => Instruction.new(:sta, :indirect_y),
      0x92 => Instruction.new(:jam, :implied, illegal: true),
      0x93 => Instruction.new(:sha, :indirect_y, illegal: true),
      0x94 => Instruction.new(:sty, :zeropage_x),
      0x95 => Instruction.new(:sta, :zeropage_x),
      0x96 => Instruction.new(:stx, :zeropage_y),
      0x97 => Instruction.new(:sax, :zeropage_y, illegal: true),
      0x98 => Instruction.new(:tya, :implied),
      0x99 => Instruction.new(:sta, :absolute_y),
      0x9a => Instruction.new(:txs, :implied),
      0x9b => Instruction.new(:tas, :absolute_y, illegal: true),
      0x9c => Instruction.new(:shy, :absolute_x, illegal: true),
      0x9d => Instruction.new(:sta, :absolute_x),
      0x9e => Instruction.new(:shx, :absolute_y, illegal: true),
      0x9f => Instruction.new(:sha, :absolute_y, illegal: true),

      0xa0 => Instruction.new(:ldy, :immediate),
      0xa1 => Instruction.new(:lda, :indirect_x),
      0xa2 => Instruction.new(:ldx, :immediate),
      0xa3 => Instruction.new(:lax, :indirect_x, illegal: true),
      0xa4 => Instruction.new(:ldy, :zeropage),
      0xa5 => Instruction.new(:lda, :zeropage),
      0xa6 => Instruction.new(:ldx, :zeropage),
      0xa7 => Instruction.new(:lax, :zeropage, illegal: true),
      0xa8 => Instruction.new(:tay, :implied),
      0xa9 => Instruction.new(:lda, :immediate),
      0xaa => Instruction.new(:tax, :implied),
      0xab => Instruction.new(:lxa, :immediate, illegal: true),
      0xac => Instruction.new(:ldy, :absolute),
      0xad => Instruction.new(:lda, :absolute),
      0xae => Instruction.new(:ldx, :absolute),
      0xaf => Instruction.new(:lax, :absolute, illegal: true),

      0xb0 => Instruction.new(:bcs, :relative),
      0xb1 => Instruction.new(:lda, :indirect_y, boundary_cycle: true),
      0xb2 => Instruction.new(:jam, :implied, illegal: true),
      0xb3 => Instruction.new(:lax, :indirect_y, boundary_cycle: true, illegal: true),
      0xb4 => Instruction.new(:ldy, :zeropage_x),
      0xb5 => Instruction.new(:lda, :zeropage_x),
      0xb6 => Instruction.new(:ldx, :zeropage_y),
      0xb7 => Instruction.new(:lax, :zeropage_y, illegal: true),
      0xb8 => Instruction.new(:clv, :implied),
      0xb9 => Instruction.new(:lda, :absolute_y, boundary_cycle: true),
      0xba => Instruction.new(:tsx, :implied),
      0xbb => Instruction.new(:las, :absolute_y, boundary_cycle: true, illegal: true),
      0xbc => Instruction.new(:ldy, :absolute_x, boundary_cycle: true),
      0xbd => Instruction.new(:lda, :absolute_x, boundary_cycle: true),
      0xbe => Instruction.new(:ldx, :absolute_y, boundary_cycle: true),
      0xbf => Instruction.new(:lax, :absolute_y, boundary_cycle: true, illegal: true),

      0xc0 => Instruction.new(:cpy, :immediate),
      0xc1 => Instruction.new(:cmp, :indirect_x),
      0xc2 => Instruction.new(:nop_nocycle, :immediate, illegal: true),
      0xc3 => Instruction.new(:dcp, :indirect_x, illegal: true),
      0xc4 => Instruction.new(:cpy, :zeropage),
      0xc5 => Instruction.new(:cmp, :zeropage),
      0xc6 => Instruction.new(:dec, :zeropage),
      0xc7 => Instruction.new(:dcp, :zeropage, illegal: true),
      0xc8 => Instruction.new(:iny, :implied),
      0xc9 => Instruction.new(:cmp, :immediate),
      0xca => Instruction.new(:dex, :implied),
      0xcb => Instruction.new(:sbx, :immediate, illegal: true),
      0xcc => Instruction.new(:cpy, :absolute),
      0xcd => Instruction.new(:cmp, :absolute),
      0xce => Instruction.new(:dec, :absolute),
      0xcf => Instruction.new(:dcp, :absolute, illegal: true),

      0xd0 => Instruction.new(:bne, :relative),
      0xd1 => Instruction.new(:cmp, :indirect_y, boundary_cycle: true),
      0xd2 => Instruction.new(:jam, :implied, illegal: true),
      0xd3 => Instruction.new(:dcp, :indirect_y, illegal: true),
      0xd4 => Instruction.new(:nop, :zeropage_x, illegal: true),
      0xd5 => Instruction.new(:cmp, :zeropage_x),
      0xd6 => Instruction.new(:dec, :zeropage_x),
      0xd7 => Instruction.new(:dcp, :zeropage_x, illegal: true),
      0xd8 => Instruction.new(:cld, :implied),
      0xd9 => Instruction.new(:cmp, :absolute_y, boundary_cycle: true),
      0xda => Instruction.new(:nop, :implied, illegal: true),
      0xdb => Instruction.new(:dcp, :absolute_y, illegal: true),
      0xdc => Instruction.new(:nop, :absolute_x, boundary_cycle: true, illegal: true),
      0xdd => Instruction.new(:cmp, :absolute_x, boundary_cycle: true),
      0xde => Instruction.new(:dec, :absolute_x),
      0xdf => Instruction.new(:dcp, :absolute_x, illegal: true),

      0xe0 => Instruction.new(:cpx, :immediate),
      0xe1 => Instruction.new(:sbc, :indirect_x),
      0xe2 => Instruction.new(:nop_nocycle, :immediate, illegal: true),
      0xe3 => Instruction.new(:isc, :indirect_x, illegal: true),
      0xe4 => Instruction.new(:cpx, :zeropage),
      0xe5 => Instruction.new(:sbc, :zeropage),
      0xe6 => Instruction.new(:inc, :zeropage),
      0xe7 => Instruction.new(:isc, :zeropage, illegal: true),
      0xe8 => Instruction.new(:inx, :implied),
      0xe9 => Instruction.new(:sbc, :immediate),
      0xea => Instruction.new(:nop, :implied),
      0xeb => Instruction.new(:sbc, :immediate, illegal: true),
      0xec => Instruction.new(:cpx, :absolute),
      0xed => Instruction.new(:sbc, :absolute),
      0xee => Instruction.new(:inc, :absolute),
      0xef => Instruction.new(:isc, :absolute, illegal: true),

      0xf0 => Instruction.new(:beq, :relative),
      0xf1 => Instruction.new(:sbc, :indirect_y, boundary_cycle: true),
      0xf2 => Instruction.new(:jam, :implied, illegal: true),
      0xf3 => Instruction.new(:isc, :indirect_y, illegal: true),
      0xf4 => Instruction.new(:nop, :zeropage_x, illegal: true),
      0xf5 => Instruction.new(:sbc, :zeropage_x),
      0xf6 => Instruction.new(:inc, :zeropage_x),
      0xf7 => Instruction.new(:isc, :zeropage_x, illegal: true),
      0xf8 => Instruction.new(:sed, :implied),
      0xf9 => Instruction.new(:sbc, :absolute_y, boundary_cycle: true),
      0xfa => Instruction.new(:nop, :implied, illegal: true),
      0xfb => Instruction.new(:isc, :absolute_y, illegal: true),
      0xfc => Instruction.new(:nop, :absolute_x, boundary_cycle: true, illegal: true),
      0xfd => Instruction.new(:sbc, :absolute_x, boundary_cycle: true),
      0xfe => Instruction.new(:inc, :absolute_x),
      0xff => Instruction.new(:isc, :absolute_x, illegal: true)
    }.freeze

    TABLE = Array.new(256) { |opcode| MAP[opcode] }.freeze

    class << self
      def map = MAP

      def find(opcode)
        TABLE[opcode.to_i]
      end
    end
  end
end
