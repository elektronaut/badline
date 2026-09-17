# frozen_string_literal: true

require "badline/instruction_set/arithmetic"
require "badline/instruction_set/bitwise"
require "badline/instruction_set/branch"
require "badline/instruction_set/inc_dec"
require "badline/instruction_set/flag"
require "badline/instruction_set/illegal"
require "badline/instruction_set/stack"
require "badline/instruction_set/transfer"

module Badline
  # http://www.6502.org/tutorials/6502opcodes.html
  # http://www.e-tradition.net/bytes/6502/6502_instruction_set.html
  #
  # The per-category modules below are included by CPU directly, not by this
  # module: a module included into a module included into a class is a shape
  # the Spinel AOT compiler loses track of, and the instruction bodies then
  # can't resolve Cycleable#cycle.
  module InstructionSet
    # Dispatches an instruction to its implementation.
    #
    # This is a case rather than `send(name, ...)` because a send with a
    # runtime method name has nothing an AOT compiler can resolve. Ruby
    # compiles an all-literal symbol case to a jump table, so the lookup
    # costs the same here.
    def execute(name, address, value)
      case name
      when :adc then adc(address, value)
      when :alr then alr(address, value)
      when :anc then anc(address, value)
      when :and then self.and(address, value)
      when :ane then ane(address, value)
      when :arr then arr(address, value)
      when :asl then asl(address, value)
      when :bcc then bcc(address, value)
      when :bcs then bcs(address, value)
      when :beq then beq(address, value)
      when :bit then bit(address, value)
      when :bmi then bmi(address, value)
      when :bne then bne(address, value)
      when :bpl then bpl(address, value)
      when :brk then brk(address, value)
      when :bvc then bvc(address, value)
      when :bvs then bvs(address, value)
      when :clc then clc(address, value)
      when :cld then cld(address, value)
      when :cli then cli(address, value)
      when :clv then clv(address, value)
      when :cmp then cmp(address, value)
      when :cpx then cpx(address, value)
      when :cpy then cpy(address, value)
      when :dcp then dcp(address, value)
      when :dec then dec(address, value)
      when :dex then dex(address, value)
      when :dey then dey(address, value)
      when :eor then eor(address, value)
      when :inc then inc(address, value)
      when :inx then inx(address, value)
      when :iny then iny(address, value)
      when :isc then isc(address, value)
      when :jam then jam(address, value)
      when :jmp then jmp(address, value)
      when :jsr then jsr(address, value)
      when :las then las(address, value)
      when :lax then lax(address, value)
      when :lda then lda(address, value)
      when :ldx then ldx(address, value)
      when :ldy then ldy(address, value)
      when :lsr then lsr(address, value)
      when :lxa then lxa(address, value)
      when :nop then nop(address, value)
      when :nop_nocycle then nop_nocycle(address, value)
      when :ora then ora(address, value)
      when :pha then pha(address, value)
      when :php then php(address, value)
      when :pla then pla(address, value)
      when :plp then plp(address, value)
      when :rla then rla(address, value)
      when :rol then rol(address, value)
      when :ror then ror(address, value)
      when :rra then rra(address, value)
      when :rti then rti(address, value)
      when :rts then rts(address, value)
      when :sax then sax(address, value)
      when :sbc then sbc(address, value)
      when :sbx then sbx(address, value)
      when :sec then sec(address, value)
      when :sed then sed(address, value)
      when :sei then sei(address, value)
      when :sha then sha(address, value)
      when :shx then shx(address, value)
      when :shy then shy(address, value)
      when :slo then slo(address, value)
      when :sre then sre(address, value)
      when :sta then sta(address, value)
      when :stx then stx(address, value)
      when :sty then sty(address, value)
      when :tas then tas(address, value)
      when :tax then tax(address, value)
      when :tay then tay(address, value)
      when :tsx then tsx(address, value)
      when :txa then txa(address, value)
      when :txs then txs(address, value)
      when :tya then tya(address, value)
      else raise CPU::InvalidOpcodeError, "unknown instruction #{name}"
      end
    end

    # Forces a software interrupt (break).
    # Pushes PC+2 and status to stack, sets break flag, and jumps via IRQ vector.
    #
    # Opcodes:
    #   $00 - implied - 7 cycles
    def brk(_addr, _value)
      status.break = true
      handle_interrupt(0xfffe, brk: true, pre_cycles: 1)
      status.break = false
    end

    # No operation. Does nothing but consume a clock cycle.
    #
    # Opcodes:
    #   $EA                          - implied    - 2 cycles
    #   $04, $44, $64                - zeropage   - 3 cycles  (illegal)
    #   $14, $34, $54, $74, $D4, $F4 - zeropage_x - 4 cycles  (illegal)
    #   $0C                          - absolute   - 4 cycles  (illegal)
    #   $1C, $3C, $5C, $7C, $DC, $FC - absolute_x - 4+ cycles (illegal)
    #   $1A, $3A, $5A, $7A, $DA, $FA - implied    - 2 cycles  (illegal)
    def nop(_addr, _value)
      cycle
    end

    private

    def resolve(value)
      if value == :lazy
        realize_value(@instruction, @operand, @address)
      elsif value.is_a?(Proc)
        value.call
      else
        value
      end
    end

    def update_number_flags(value)
      status.zero = value.zero?
      status.negative = value.anybits?(0x80)
      value
    end

    # Read-modify-write instructions put the unmodified value back on the bus before writing the result.
    def write_modified(addr, original, result)
      if addr == :accumulator
        cycle { @a = result }
      else
        write_byte(addr, original)
        write_byte(addr, result)
      end
    end
  end
end
