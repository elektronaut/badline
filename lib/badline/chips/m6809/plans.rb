# frozen_string_literal: true

module Badline
  module Chips
    class M6809
      # The condition code bits.
      CARRY = 0x01
      OVERFLOW = 0x02
      ZERO = 0x04
      NEGATIVE = 0x08
      IRQ_MASK = 0x10
      HALF_CARRY = 0x20
      FIRQ_MASK = 0x40
      ENTIRE = 0x80

      # What an opcode runs: the instruction method its *_exec step calls,
      # the steps that work out its address, one a cycle, and the steps
      # that follow them, and the group the undocumented stores immediate
      # take their flags from when it ran before them. An indexed opcode's
      # address steps end in the postbyte, which picks the rest from
      # INDEXED_PLANS.
      Entry = Struct.new(:operation, :plan, :tail, :group)

      # The groups of David Banks' "Flags for unprefixed Store Immediate".
      GROUP_OTHER = 0
      GROUP_N0_Z1 = 1
      GROUP_A_00 = 2
      GROUP_A_FF = 3
      GROUP_A_01 = 4
      GROUP_B_01 = 5
      GROUP_WORD_01 = 6
      GROUP_LEA = 7
      GROUPS = {
        GROUP_N0_Z1 => %i[bita cmpa],
        GROUP_A_00 => %i[lda ldd],
        GROUP_A_FF => %i[adca adda anda eora ora sbca suba],
        GROUP_A_01 => %i[asla asra coma daa deca inca lsra nega rola rora subd tsta xdeca xnca],
        GROUP_B_01 => %i[sex],
        GROUP_WORD_01 => %i[cmpd cmps cmpu cmpx cmpy xaddd xaddu],
        GROUP_LEA => %i[leas leau leax leay]
      }.flat_map { |group, operations| operations.map { |operation| [operation, group] } }.to_h.freeze

      # The plan between instructions: the next cycle fetches an opcode.
      FETCH_PLAN = %i[fetch].freeze

      # The tail an instruction has once it is running its tail, never run.
      # The empty tail, JUMP_TAIL, runs the instruction method as the
      # address steps end.
      NO_TAIL = %i[none].freeze
      JUMP_TAIL = [].freeze

      DIRECT_PLAN = %i[direct dead_v].freeze
      EXTENDED_PLAN = %i[extended_hi extended_lo dead_v].freeze
      INDEXED_PLAN = %i[postbyte].freeze

      # The steps that read or write the address once it is known.
      TAILS = {
        read8: %i[read_exec],
        read16: %i[read_hi read_lo_exec],
        read16_dead: %i[read_hi read_lo_exec dead_v],
        write8: %i[write_exec],
        write16: %i[write_hi_exec write_lo],
        rmw: %i[rmw_read dead_v rmw_write],
        test: %i[read_exec dead_v dead_v],
        jump: JUMP_TAIL,
        subroutine: %i[dead_ea dead_v push_pcl push_pch_exec],
        load_address: %i[dead_v_exec]
      }.freeze

      IMMEDIATE_TAILS = {
        read8: %i[immediate_exec],
        read16: %i[immediate_hi immediate_lo_exec],
        read16_dead: %i[immediate_hi immediate_lo_exec dead_v]
      }.freeze

      # The 12 bytes SWI and the hardware interrupts other than FIRQ stack,
      # in the order they go onto S.
      PUSH_ALL = %i[push_pcl push_pch push_wl push_wh push_yl push_yh push_xl push_xh push_dp push_b push_a
                    push_cc].freeze
      VECTOR_STEPS = %i[dead_v vector_hi vector_lo dead_v].freeze

      # SWI, SWI2, SWI3 and the undocumented XRES, XSWI2 and XFIRQ, after
      # the opcode. The instruction method picks the vector.
      SOFTWARE_INTERRUPT_TAIL = [:dead_pc, :dead_v_exec, *PUSH_ALL, *VECTOR_STEPS].freeze

      # IRQ and NMI after the cycle that would have fetched the opcode, and
      # FIRQ, which stacks only PC and CC.
      INTERRUPT_PLAN = [:dead_pc, :dead_v_exec, *PUSH_ALL, *VECTOR_STEPS].freeze
      FAST_INTERRUPT_PLAN = [:dead_pc, :dead_v_exec, :push_pcl, :push_pch, :push_cc, *VECTOR_STEPS].freeze

      # The interrupt CWAI was waiting for: its vector, no more stacking.
      WAITED_INTERRUPT_PLAN = %i[vector_hi vector_lo dead_v].freeze

      # RTI after pulling CC, with E set and with E clear.
      RETURN_ENTIRE_PLAN = %i[pull_a pull_b pull_dp pull_xh pull_xl pull_yh pull_yl pull_wh pull_wl pull_pch pull_pcl
                              dead_stack].freeze
      RETURN_FAST_PLAN = %i[pull_pch pull_pcl dead_stack].freeze

      # The cycles after RESET goes high: two dead reads of $FFFE, the
      # vector, and a dead cycle.
      RESET_PLAN = %i[reset_dead reset_dead reset_hi reset_lo dead_v].freeze

      LONG_BRANCH_TAKEN_PLAN = %i[dead_v_take].freeze
      SYNC_END_PLAN = %i[idle].freeze

      # PSH and PUL by postbyte: the bytes in the order they go onto or
      # come off the stack, PC first on and last off.
      PUSH_ORDER = [[0x80, %i[push_pcl push_pch]], [0x40, %i[push_wl push_wh]], [0x20, %i[push_yl push_yh]],
                    [0x10, %i[push_xl push_xh]], [0x08, %i[push_dp]], [0x04, %i[push_b]], [0x02, %i[push_a]],
                    [0x01, %i[push_cc]]].freeze
      PULL_ORDER = [[0x01, %i[pull_cc]], [0x02, %i[pull_a]], [0x04, %i[pull_b]], [0x08, %i[pull_dp]],
                    [0x10, %i[pull_xh pull_xl]], [0x20, %i[pull_yh pull_yl]], [0x40, %i[pull_wh pull_wl]],
                    [0x80, %i[pull_pch pull_pcl]]].freeze
      PUSH_PLANS = Array.new(256) do |mask|
        [:dead_v, :dead_v, :dead_stack, *PUSH_ORDER.flat_map { |bit, steps| mask.nobits?(bit) ? [] : steps }].freeze
      end.freeze
      PULL_PLANS = Array.new(256) do |mask|
        [:dead_v, :dead_v, *PULL_ORDER.flat_map { |bit, steps| mask.nobits?(bit) ? [] : steps }, :dead_stack].freeze
      end.freeze

      # The steps after the postbyte, by postbyte, Figure 17 sheet 4.
      INDEXED_PLANS = Array.new(256) do |post|
        next %i[dead_pc dead_v].freeze if post < 0x80

        plan = case post & 0x0f
               when 0x0, 0x2 then %i[dead_pc dead_v dead_v]
               when 0x1, 0x3 then %i[dead_pc dead_v dead_v dead_v]
               when 0x4 then %i[dead_pc]
               when 0x5, 0x6 then %i[dead_pc dead_v]
               when 0x8 then %i[offset8 dead_v]
               when 0x9 then %i[offset_hi offset_lo_register dead_pc dead_v dead_v]
               when 0xb then %i[dead_pc dead_pc_next dead_pc_next2 dead_v dead_v]
               when 0xc then %i[offset8_pc dead_v]
               when 0xd then %i[offset_hi offset_lo_pc dead_pc dead_v dead_v dead_v]
               when 0xf then %i[offset_hi offset_lo_absolute dead_pc]
               else []
               end
        plan += %i[indirect_hi indirect_lo dead_v] if post.anybits?(0x10)
        plan.freeze
      end.freeze
    end
  end
end
