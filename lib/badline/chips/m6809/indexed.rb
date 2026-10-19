# frozen_string_literal: true

module Badline
  module Chips
    class M6809
      # Indexed addressing: the postbyte, and the steps INDEXED_PLANS run
      # after it.
      module Indexed
        private

        # Reads the postbyte, works out every address that needs no more
        # bytes, and moves on to the postbyte's plan. The undefined
        # postbytes $x7, $xA and $xE address $0000 and take no cycles.
        def postbyte
          post = read_pc
          @post = post
          if post < 0x80
            @ea = (index_register + (post & 0x0f) - (post & 0x10)) & 0xffff
          else
            register_address(post & 0x0f)
          end
          plan = INDEXED_PLANS[post]
          return next_plan if plan.empty?

          switch_to(plan)
        end

        def register_address(mode)
          case mode
          when 0x0 then post_increment(1)
          when 0x1 then post_increment(2)
          when 0x2 then pre_decrement(1)
          when 0x3 then pre_decrement(2)
          when 0x4 then @ea = index_register
          when 0x5 then @ea = (index_register + signed8(@b)) & 0xffff
          when 0x6 then @ea = (index_register + signed8(@a)) & 0xffff
          when 0xb then @ea = (index_register + d) & 0xffff
          when 0x7, 0xa, 0xe then @ea = 0
          end
        end

        def post_increment(amount)
          @ea = index_register
          self.index_register = (@ea + amount) & 0xffff
        end

        def pre_decrement(amount)
          @ea = (index_register - amount) & 0xffff
          self.index_register = @ea
        end

        def signed8(value) = value - ((value & 0x80) << 1)

        def offset8
          @ea = (index_register + signed8(read_pc)) & 0xffff
        end

        def offset8_pc
          offset = signed8(read_pc)
          @ea = (@pc + offset) & 0xffff
        end

        def offset_lo_register
          @value |= read_pc
          @ea = (index_register + @value) & 0xffff
        end

        def offset_lo_absolute
          @ea = @value | read_pc
        end

        def indirect_hi
          @value = @bus.read(@ea) << 8
        end

        def indirect_lo
          @ea = @value | @bus.read((@ea + 1) & 0xffff)
        end
      end
    end
  end
end
