# frozen_string_literal: true

module Badline
  class CPU
    class InvalidOpcodeError < StandardError; end

    # Micro-operations that drive a write. The bus has to know a cycle
    # ahead, so every plan carries a parallel mask built from this list.
    WRITE_STEPS = %i[op_mem_write op_rmw_write_original op_rmw_write_result
                     op_push_exec op_jsr_push_high op_jsr_push_low
                     op_int_push_pch op_int_push_pcl op_int_push_status].freeze

    # Cycles each addressing mode spends resolving its effective address,
    # between the opcode fetch and the operation itself.
    ADDRESSING_STEPS = {
      zeropage: %i[op_zp],
      zeropage_x: %i[op_zp op_zp_x],
      zeropage_y: %i[op_zp op_zp_y],
      absolute: %i[op_abs_low op_abs_high],
      absolute_x: %i[op_abs_low op_abs_high_x op_idx_dummy],
      absolute_y: %i[op_abs_low op_abs_high_y op_idx_dummy],
      indirect_x: %i[op_zp_pointer op_pointer_x op_pointer_low op_pointer_high],
      indirect_y: %i[op_zp_pointer op_pointer_low op_pointer_high_y op_idx_dummy]
    }.freeze

    # Cycles the operation spends on its operand once the address is known.
    OPERATION_STEPS = {
      read: %i[op_mem_read],
      write: %i[op_mem_write],
      rmw: %i[op_rmw_read op_rmw_write_original op_rmw_write_result]
    }.freeze

    STORES = %i[sta stx sty sax sha shx shy tas].freeze
    READ_MODIFY_WRITES = %i[asl lsr rol ror inc dec
                            slo sre rla rra isc dcp].freeze
    BRANCHES = %i[bcc bcs beq bmi bne bpl bvc bvs].freeze

    # A jammed 6502 idles forever with its address bus parked on the
    # interrupt vectors; the sequence is cut short here so tests terminate.
    JAM_ADDRESSES = [0xffff, 0xfffe, 0xfffe, 0xffff, 0xffff,
                     0xffff, 0xffff, 0xffff, 0xffff].freeze

    # The sequencer parks here between instructions.
    FETCH_PLAN = %i[op_fetch].freeze

    IMPLIED_PLAN = %i[op_fetch op_implied_exec].freeze
    ACCUMULATOR_PLAN = %i[op_fetch op_accumulator_exec].freeze
    IMMEDIATE_PLAN = %i[op_fetch op_immediate_read].freeze

    # $10, $30, $50, $70, $90, $B0, $D0, $F0 - relative - 2+ cycles.
    # A branch not taken stops after its operand; a taken one costs a
    # cycle, and a second when the target lands on another page.
    BRANCH_PLAN = %i[op_fetch op_relative op_branch op_branch_fixup].freeze

    # $4C - absolute - 3 cycles
    JMP_ABSOLUTE_PLAN = %i[op_fetch op_abs_low op_jmp_high].freeze

    # $6C - indirect - 5 cycles
    JMP_INDIRECT_PLAN = %i[op_fetch op_abs_low op_abs_high
                           op_indirect_low op_indirect_high].freeze

    # $20 - absolute - 6 cycles
    JSR_PLAN = %i[op_fetch op_jsr_low op_jsr_dummy
                  op_jsr_push_high op_jsr_push_low op_jsr_high].freeze

    # $60 - implied - 6 cycles
    RTS_PLAN = %i[op_fetch op_implied_dummy op_pull_dummy
                  op_pull_low op_pull_high op_rts_fixup].freeze

    # $40 - implied - 6 cycles
    RTI_PLAN = %i[op_fetch op_implied_dummy op_pull_dummy
                  op_rti_pull_status op_pull_low op_rti_pull_high].freeze

    # $08, $48 - implied - 3 cycles
    PUSH_PLAN = %i[op_fetch op_implied_dummy op_push_exec].freeze

    # $28, $68 - implied - 4 cycles
    PULL_PLAN = %i[op_fetch op_implied_dummy op_pull_dummy op_pull_exec].freeze

    # $02, $12, $22, $32, $42, $52, $62, $72, $92, $B2, $D2, $F2
    JAM_PLAN = [:op_fetch, :op_implied_dummy,
                *Array.new(JAM_ADDRESSES.length, :op_jam)].freeze

    # BRK and a hardware interrupt run the same push-and-vector sequence:
    # the return address and status go on the stack, then the vector is
    # read. They differ only in their second cycle, where BRK ($00,
    # implied, 7 cycles) arms the vector and the break flag it pushes.
    INTERRUPT_PLAN = %i[op_fetch op_implied_dummy
                        op_int_push_pch op_int_push_pcl op_int_push_status
                        op_int_vector_low op_int_vector_high].freeze
    BRK_PLAN = %i[op_fetch op_brk_dummy
                  op_int_push_pch op_int_push_pcl op_int_push_status
                  op_int_vector_low op_int_vector_high].freeze

    SPECIAL_PLANS = {
      brk: BRK_PLAN, jam: JAM_PLAN, jsr: JSR_PLAN, rts: RTS_PLAN,
      rti: RTI_PLAN, pha: PUSH_PLAN, php: PUSH_PLAN,
      pla: PULL_PLAN, plp: PULL_PLAN
    }.freeze

    # One opcode's cycle plan. +plan+ names the micro-operation run on each
    # cycle, +writes+ marks which of them poke memory, and +optional_dummy+
    # marks the indexed modes whose fixup cycle only runs when the index
    # carries into the high byte.
    Microcode = Struct.new(:operation, :plan, :writes, :optional_dummy) do
      class << self
        def table
          Array.new(256) do |opcode|
            instruction = Instruction.find(opcode)
            raise InvalidOpcodeError, format("$%02x", opcode) unless instruction

            build(instruction)
          end.freeze
        end

        def write_mask(plan)
          plan.map { |step| WRITE_STEPS.include?(step) }.freeze
        end

        private

        def build(instruction)
          plan = plan_for(instruction)
          new(instruction.name, plan, write_mask(plan),
              instruction.boundary_cycle?)
        end

        def plan_for(instruction)
          case instruction.name
          when :jmp
            if instruction.addressing_mode == :indirect
              JMP_INDIRECT_PLAN
            else
              JMP_ABSOLUTE_PLAN
            end
          when *BRANCHES then BRANCH_PLAN
          else SPECIAL_PLANS[instruction.name] || addressed_plan(instruction)
          end
        end

        def addressed_plan(instruction)
          mode = instruction.addressing_mode
          case mode
          when :implied then IMPLIED_PLAN
          when :accumulator then ACCUMULATOR_PLAN
          when :immediate then IMMEDIATE_PLAN
          else
            [:op_fetch, *ADDRESSING_STEPS.fetch(mode),
             *OPERATION_STEPS.fetch(operation_kind(instruction.name))].freeze
          end
        end

        def operation_kind(name)
          return :write if STORES.include?(name)
          return :rmw if READ_MODIFY_WRITES.include?(name)

          :read
        end
      end
    end

    FETCH_WRITES = Microcode.write_mask(FETCH_PLAN)
    INTERRUPT_WRITES = Microcode.write_mask(INTERRUPT_PLAN)
    MICROCODE = Microcode.table
  end
end
