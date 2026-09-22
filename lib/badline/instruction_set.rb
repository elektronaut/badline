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
  module InstructionSet
    include InstructionSet::Arithmetic
    include InstructionSet::Bitwise
    include InstructionSet::Branch
    include InstructionSet::IncDec
    include InstructionSet::Flag
    include InstructionSet::Illegal
    include InstructionSet::Stack
    include InstructionSet::Transfer

    # Forces a software interrupt (break).
    # Pushes PC+2 and status to stack, sets break flag, and jumps via IRQ vector.
    #
    # Opcodes:
    #   $00 - implied - 7 cycles
    def brk(_addr, _value)
      status.break = true
      handle_interrupt(0xfffe, brk: true)
      status.break = false
    end

    # No operation. The implied forms idle; the illegal memory forms still
    # read their operand and throw it away.
    #
    # Opcodes:
    #   $EA                          - implied    - 2 cycles
    #   $04, $44, $64                - zeropage   - 3 cycles  (illegal)
    #   $14, $34, $54, $74, $D4, $F4 - zeropage_x - 4 cycles  (illegal)
    #   $0C                          - absolute   - 4 cycles  (illegal)
    #   $1C, $3C, $5C, $7C, $DC, $FC - absolute_x - 4+ cycles (illegal)
    #   $1A, $3A, $5A, $7A, $DA, $FA - implied    - 2 cycles  (illegal)
    def nop(addr, value)
      resolve(value) unless addr.nil?
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
        @a = result
      else
        write_byte(addr, original)
        write_byte(addr, result)
      end
    end
  end
end
