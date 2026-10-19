# frozen_string_literal: true

module Badline
  module Chips
    class M6809
      # The stack steps of PSH, PUL, JSR, BSR, RTS, RTI, the software
      # interrupts and the hardware ones. Each pushes onto or pulls off the
      # stack @stack_u names: U for PSHU and PULU, S otherwise. The "other"
      # stack pointer, w, is the one that isn't.
      module Stack
        private

        def push(value)
          if @stack_u
            @u = (@u - 1) & 0xffff
            @bus.write(@u, value)
          else
            @s = (@s - 1) & 0xffff
            @bus.write(@s, value)
          end
        end

        def pull
          if @stack_u
            value = @bus.read(@u)
            @u = (@u + 1) & 0xffff
          else
            value = @bus.read(@s)
            @s = (@s + 1) & 0xffff
          end
          value
        end

        def dead_stack = @bus.read(@stack_u ? @u : @s)

        def other_stack = @stack_u ? @s : @u

        def other_stack=(value)
          @stack_u ? load_s(value) : @u = value
        end

        def push_s_post = stack_post(false, PUSH_PLANS)

        def push_u_post = stack_post(true, PUSH_PLANS)

        def pull_s_post = stack_post(false, PULL_PLANS)

        def pull_u_post = stack_post(true, PULL_PLANS)

        def stack_post(stack_u, plans)
          @stack_u = stack_u
          switch_to(plans[read_pc])
        end

        def push_pcl = push(@pc & 0xff)
        def push_pch = push(@pc >> 8)
        def push_wl = push(other_stack & 0xff)
        def push_wh = push(other_stack >> 8)
        def push_yl = push(@y & 0xff)
        def push_yh = push(@y >> 8)
        def push_xl = push(@x & 0xff)
        def push_xh = push(@x >> 8)
        def push_dp = push(@dp)
        def push_b = push(@b)
        def push_a = push(@a)
        def push_cc = push(@cc)

        def push_pch_exec
          push_pch
          send(@operation)
        end

        def pull_cc
          @cc = pull
        end

        def pull_a
          @a = pull
        end

        def pull_b
          @b = pull
        end

        def pull_dp
          @dp = pull
        end

        def pull_xh
          @x = (pull << 8) | (@x & 0xff)
        end

        def pull_xl
          @x = (@x & 0xff00) | pull
        end

        def pull_yh
          @y = (pull << 8) | (@y & 0xff)
        end

        def pull_yl
          @y = (@y & 0xff00) | pull
        end

        def pull_wh
          self.other_stack = (pull << 8) | (other_stack & 0xff)
        end

        def pull_wl
          self.other_stack = (other_stack & 0xff00) | pull
        end

        def pull_pch
          @pc = (pull << 8) | (@pc & 0xff)
        end

        def pull_pcl
          @pc = (@pc & 0xff00) | pull
        end

        # RTI after pulling CC: the whole state when E is set, else PC.
        def return_cc
          pull_cc
          switch_to(@cc.nobits?(ENTIRE) ? RETURN_FAST_PLAN : RETURN_ENTIRE_PLAN)
        end

        # The vector of the interrupt or SWI being taken. The masks it sets
        # take effect as its first byte is read.
        def vector_hi
          @value = @bus.read(@vector) << 8
          @cc |= @interrupt_mask
        end

        def vector_lo
          @pc = @value | @bus.read(@vector + 1)
        end
      end
    end
  end
end
