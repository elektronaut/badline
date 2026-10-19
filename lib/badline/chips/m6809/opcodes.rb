# frozen_string_literal: true

require "badline/chips/m6809/plans"

module Badline
  module Chips
    class M6809
      # The read-modify-write group: $00-$0F direct, $60-$6F indexed and
      # $70-$7F extended, and $40-$4F and $50-$5F on A and B.
      MEMORY_GROUP = %i[neg neg xnc com lsr lsr ror asr asl rol dec xdec inc tst jmp clr].freeze
      A_GROUP = %i[nega nega xnca coma lsra lsra rora asra asla rola deca xdeca inca tsta xclra clra].freeze
      B_GROUP = %i[negb negb xncb comb lsrb lsrb rorb asrb aslb rolb decb xdecb incb tstb xclrb clrb].freeze

      # $80-$BF and $C0-$FF by low nibble: the instruction and its kind.
      A_COLUMN = [%i[suba read8], %i[cmpa read8], %i[sbca read8], %i[subd read16_dead], %i[anda read8],
                  %i[bita read8], %i[lda read8], %i[sta write8], %i[eora read8], %i[adca read8], %i[ora read8],
                  %i[adda read8], %i[cmpx read16_dead], %i[jsr subroutine], %i[ldx read16], %i[stx write16]].freeze
      B_COLUMN = [%i[subb read8], %i[cmpb read8], %i[sbcb read8], %i[addd read16_dead], %i[andb read8],
                  %i[bitb read8], %i[ldb read8], %i[stb write8], %i[eorb read8], %i[adcb read8], %i[orb read8],
                  %i[addb read8], %i[ldd read16], %i[std write16], %i[ldu read16], %i[stu write16]].freeze
      PAGE2_COLUMN = { 0x3 => %i[cmpd read16_dead], 0xc => %i[cmpy read16_dead], 0xe => %i[ldy read16],
                       0xf => %i[sty write16] }.freeze
      PAGE2_B_COLUMN = { 0x3 => %i[xaddd read16_dead], 0xe => %i[lds read16], 0xf => %i[sts write16] }.freeze
      PAGE3_COLUMN = { 0x3 => %i[cmpu read16_dead], 0xc => %i[cmps read16_dead] }.freeze
      PAGE3_B_COLUMN = { 0x3 => %i[xaddu read16_dead] }.freeze

      # Opcodes with a plan of their own, after the opcode fetch.
      INHERENT = {
        0x12 => [:nop, %i[dead_pc_exec]],
        0x13 => [:sync, %i[dead_pc sync_wait]],
        0x14 => [:none, %i[free_run]],
        0x15 => [:none, %i[free_run]],
        0x16 => [:jmp, %i[offset_hi offset_lo_pc dead_v dead_v_exec]],
        0x17 => [:jsr, %i[offset_hi offset_lo_pc dead_v dead_v dead_ea dead_v push_pcl push_pch_exec]],
        0x18 => [:x18, %i[next_byte_exec]],
        0x19 => [:daa, %i[dead_pc_exec]],
        0x1a => [:orcc, %i[immediate_exec dead_pc]],
        0x1b => [:nop, %i[dead_pc_exec]],
        0x1c => [:andcc, %i[immediate_exec dead_pc]],
        0x1d => [:sex, %i[dead_pc_exec]],
        0x1e => [:exg, %i[read_post dead_v dead_v dead_v dead_v dead_v dead_v_exec]],
        0x1f => [:tfr, %i[read_post dead_v dead_v dead_v dead_v_exec]],
        0x34 => [:none, %i[push_s_post]],
        0x35 => [:none, %i[pull_s_post]],
        0x36 => [:none, %i[push_u_post]],
        0x37 => [:none, %i[pull_u_post]],
        0x38 => [:andcc, %i[idle immediate_exec dead_pc]],
        0x39 => [:none, %i[dead_pc pull_pch pull_pcl dead_v]],
        0x3a => [:abx, %i[dead_pc dead_v_exec]],
        0x3b => [:none, %i[dead_pc return_cc]],
        0x3c => [:none, [:cwai_mask, :dead_pc, :dead_v, *PUSH_ALL, :cwai_wait]],
        0x3d => [:mul, %i[dead_pc dead_v dead_v dead_v dead_v dead_v dead_v dead_v dead_v dead_v_exec]],
        0x3e => [:xres, SOFTWARE_INTERRUPT_TAIL],
        0x3f => [:swi, SOFTWARE_INTERRUPT_TAIL],
        0x87 => [:xsta, %i[immediate_exec]],
        0x8d => [:jsr, %i[offset8_branch dead_v dead_ea dead_v push_pcl push_pch_exec]],
        0x8f => [:xstx, %i[immediate_discard store_immediate]],
        0xc7 => [:xstb, %i[immediate_exec]],
        0xcd => [:none, %i[free_run]],
        0xcf => [:xstu, %i[immediate_discard store_immediate]]
      }.freeze

      PAGE2_INHERENT = {
        0x3e => [:xswi2, SOFTWARE_INTERRUPT_TAIL],
        0x3f => [:swi2, SOFTWARE_INTERRUPT_TAIL],
        0x87 => [:xsta2, %i[immediate_exec]],
        0x8f => [:xsty, %i[immediate_discard store_immediate]],
        0xc7 => [:xstb2, %i[immediate_exec]],
        0xcf => [:xsts, %i[immediate_discard store_immediate]]
      }.freeze

      PAGE3_INHERENT = {
        0x3e => [:xfirq, SOFTWARE_INTERRUPT_TAIL],
        0x3f => [:swi3, SOFTWARE_INTERRUPT_TAIL],
        0x87 => [:xsta2, %i[immediate_exec]],
        0x8f => [:xstx2, %i[immediate_discard store_immediate]],
        0xc7 => [:xstb2, %i[immediate_exec]],
        0xcf => [:xstu2, %i[immediate_discard store_immediate]]
      }.freeze

      SHORT_BRANCH_TAIL = %i[offset8_branch dead_v_branch].freeze
      LONG_BRANCH_TAIL = %i[offset_hi offset_lo_pc dead_v_long_branch].freeze
      LEA = { 0x30 => :leax, 0x31 => :leay, 0x32 => :leas, 0x33 => :leau }.freeze

      # Builds the opcode tables.
      module Opcodes
        MODES = [nil, DIRECT_PLAN, INDEXED_PLAN, EXTENDED_PLAN].freeze

        module_function

        def entry(operation, plan, tail) = Entry.new(operation, plan.freeze, tail.freeze)

        def tail(kind, mode)
          return IMMEDIATE_TAILS.fetch(kind) if mode.zero?

          TAILS.fetch(kind)
        end

        def memory(opcode)
          mode = if opcode < 0x10 then DIRECT_PLAN
                 elsif opcode < 0x70 then INDEXED_PLAN
                 else EXTENDED_PLAN
                 end
          name = MEMORY_GROUP[opcode & 0x0f]
          entry(name, mode, TAILS.fetch({ tst: :test, jmp: :jump }.fetch(name, :rmw)))
        end

        # $80-$FF: immediate, direct, indexed and extended by bits 4 and 5.
        def column(opcode, column)
          name, kind = column.fetch(opcode & 0x0f)
          mode = (opcode >> 4) & 0x3
          return entry(:none, [], NO_TAIL) if mode.zero? && !IMMEDIATE_TAILS.key?(kind)

          entry(name, mode.zero? ? [] : MODES.fetch(mode), tail(kind, mode))
        end

        def page1(opcode)
          if (inherent = INHERENT[opcode]) then entry(inherent[0], [], inherent[1])
          elsif opcode < 0x10 || (0x60..0x7f).cover?(opcode) then memory(opcode)
          elsif (0x40..0x5f).cover?(opcode) then inherent_register(opcode)
          elsif (0x20..0x2f).cover?(opcode) then entry(:none, [], SHORT_BRANCH_TAIL)
          elsif LEA.key?(opcode) then entry(LEA[opcode], INDEXED_PLAN, TAILS[:load_address])
          elsif opcode >= 0x80 then column(opcode, opcode >= 0xc0 ? B_COLUMN : A_COLUMN)
          else entry(:none, [], NO_TAIL)
          end
        end

        def inherent_register(opcode)
          name = (opcode < 0x50 ? A_GROUP : B_GROUP)[opcode & 0x0f]
          entry(name, [], %i[dead_pc_exec])
        end

        # Pages 2 and 3. An opcode a page doesn't define runs as on page 1,
        # after the prefix's cycle.
        def paged(opcode, page1, inherent, columns)
          return entry(inherent[opcode][0], [], inherent[opcode][1]) if inherent.key?(opcode)
          return entry(:none, [], LONG_BRANCH_TAIL) if columns.first == PAGE2_COLUMN && (0x20..0x2f).cover?(opcode)

          column = opcode >= 0xc0 ? columns[1] : columns[0]
          return page1[opcode] if opcode < 0x80 || !column.key?(opcode & 0x0f)

          name, kind = column[opcode & 0x0f]
          mode = (opcode >> 4) & 0x3
          entry(name, mode.zero? ? [] : MODES.fetch(mode), tail(kind, mode))
        end
      end

      PAGE1 = Array.new(256) { |opcode| Opcodes.page1(opcode) }.freeze
      PAGE2 = Array.new(256) do |opcode|
        Opcodes.paged(opcode, PAGE1, PAGE2_INHERENT, [PAGE2_COLUMN, PAGE2_B_COLUMN])
      end.freeze
      PAGE3 = Array.new(256) do |opcode|
        Opcodes.paged(opcode, PAGE1, PAGE3_INHERENT, [PAGE3_COLUMN, PAGE3_B_COLUMN])
      end.freeze
    end
  end
end
