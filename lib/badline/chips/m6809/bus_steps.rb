# frozen_string_literal: true

module Badline
  module Chips
    class M6809
      PREFIX_PLAN = %i[fetch_paged].freeze

      # The steps that fetch opcodes and operands, work out direct and
      # extended addresses and branch targets, and read and write the
      # operand, one bus cycle each.
      module BusSteps
        private

        def read_pc
          value = @bus.read(@pc)
          @pc = (@pc + 1) & 0xffff
          value
        end

        def fetch
          return halted_cycle if @halt_seen
          return take_interrupt if interrupt_due?

          opcode = read_pc
          @opcode = opcode
          case opcode
          when 0x10
            @page = PAGE2
            switch_to(PREFIX_PLAN)
          when 0x11
            @page = PAGE3
            switch_to(PREFIX_PLAN)
          else start(PAGE1[opcode])
          end
        end

        # The opcode after a prefix. A further prefix only costs a cycle.
        def fetch_paged
          opcode = read_pc
          return @index -= 1 if [0x10, 0x11].include?(opcode)

          @opcode = opcode
          start(@page[opcode])
        end

        def dead_pc = @bus.read(@pc)

        def dead_pc_next = @bus.read((@pc + 1) & 0xffff)

        def dead_pc_next2 = @bus.read((@pc + 2) & 0xffff)

        def dead_v = @bus.read(0xffff)

        def dead_ea = @bus.read(@ea)

        # A cycle without a bus access.
        def idle; end

        def dead_pc_exec
          dead_pc
          execute
        end

        # A dead read of the byte after the opcode, which the undocumented
        # $18 uses.
        def next_byte_exec
          @value = @bus.read(@pc)
          execute
        end

        def dead_v_exec
          dead_v
          execute
        end

        def direct
          @ea = (@dp << 8) | read_pc
        end

        def extended_hi
          @ea = read_pc << 8
        end

        def extended_lo
          @ea |= read_pc
        end

        def immediate_exec
          @value = read_pc
          execute
        end

        def immediate_hi
          @value = read_pc << 8
        end

        def immediate_lo_exec
          @value |= read_pc
          execute
        end

        def immediate_discard = read_pc

        # The undocumented 16-bit stores immediate write the register's low
        # byte over the operand's.
        def store_immediate
          execute
          @bus.write(@pc, @value)
          @pc = (@pc + 1) & 0xffff
        end

        def read_post
          @post = read_pc
        end

        def read_exec
          @value = @bus.read(@ea)
          execute
        end

        def read_hi
          @value = @bus.read(@ea) << 8
        end

        def read_lo_exec
          @value |= @bus.read((@ea + 1) & 0xffff)
          execute
        end

        def write_exec
          execute
          @bus.write(@ea, @value)
        end

        def write_hi_exec
          execute
          @bus.write(@ea, @value >> 8)
        end

        def write_lo
          @bus.write((@ea + 1) & 0xffff, @value & 0xff)
        end

        def rmw_read
          @value = @bus.read(@ea)
          execute
        end

        def rmw_write
          @bus.write(@ea, @value)
        end

        # A short branch's offset, and the target it gives.
        def offset8_branch
          offset = read_pc
          @ea = (@pc + offset - ((offset & 0x80) * 2)) & 0xffff
        end

        def offset_hi
          @value = read_pc << 8
        end

        # The low byte of a 16-bit offset from PC, and its target.
        def offset_lo_pc
          @value |= read_pc
          @ea = (@pc + @value) & 0xffff
        end

        def dead_v_branch
          dead_v
          @pc = @ea if condition?(@opcode)
        end

        # A long branch taken takes one more cycle.
        def dead_v_long_branch
          dead_v
          switch_to(LONG_BRANCH_TAKEN_PLAN) if condition?(@opcode)
        end

        def dead_v_take
          dead_v
          @pc = @ea
        end

        # The undocumented $14, $15 and $CD read on from PC, a byte a cycle,
        # until reset.
        def free_run
          read_pc
          @index -= 1
        end

        def condition?(opcode)
          cc = @cc
          case opcode & 0x0f
          when 0x0 then true
          when 0x1 then false
          when 0x2 then cc.nobits?(CARRY | ZERO)
          when 0x3 then cc.anybits?(CARRY | ZERO)
          when 0x4 then cc.nobits?(CARRY)
          when 0x5 then cc.anybits?(CARRY)
          when 0x6 then cc.nobits?(ZERO)
          when 0x7 then cc.anybits?(ZERO)
          when 0x8 then cc.nobits?(OVERFLOW)
          when 0x9 then cc.anybits?(OVERFLOW)
          when 0xa then cc.nobits?(NEGATIVE)
          when 0xb then cc.anybits?(NEGATIVE)
          else signed_condition?(opcode, cc)
          end
        end

        def signed_condition?(opcode, cc)
          less = cc.anybits?(NEGATIVE) != cc.anybits?(OVERFLOW)
          case opcode & 0x0f
          when 0xc then !less
          when 0xd then less
          when 0xe then !less && cc.nobits?(ZERO)
          else less || cc.anybits?(ZERO)
          end
        end
      end
    end
  end
end
