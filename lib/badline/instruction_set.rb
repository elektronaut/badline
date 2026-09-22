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

    # No operation. The illegal forms with an operand still read it, in
    # the steps before this is called.
    #
    # Opcodes:
    #   $EA                          - implied    - 2 cycles
    #   $04, $44, $64                - zeropage   - 3 cycles  (illegal)
    #   $14, $34, $54, $74, $D4, $F4 - zeropage_x - 4 cycles  (illegal)
    #   $0C                          - absolute   - 4 cycles  (illegal)
    #   $1C, $3C, $5C, $7C, $DC, $FC - absolute_x - 4+ cycles (illegal)
    #   $1A, $3A, $5A, $7A, $DA, $FA - implied    - 2 cycles  (illegal)
    def nop(_addr, _value); end

    private

    def update_number_flags(value)
      status.zero = value.zero?
      status.negative = value.anybits?(0x80)
      value
    end

    # Stores a read-modify-write result. For memory, the write happens in
    # the steps that follow (see Operations#op_rmw_read).
    def write_modified(addr, result)
      if addr == :accumulator
        @a = result
      else
        @rmw_result = result
      end
    end
  end
end
