# frozen_string_literal: true

module Badline
  module Chips
    class M6809
      # The programmer's registers, and the codes TFR and EXG and the
      # indexed postbyte name them by.
      module Registers
        attr_accessor :a, :b, :x, :y, :u, :s, :pc, :dp, :cc

        def d = (@a << 8) | @b

        def d=(value)
          @a = value >> 8
          @b = value & 0xff
        end

        # Whether NMI is armed: a load of S since reset.
        def nmi_armed? = @nmi_armed

        private

        def load_s(value)
          @s = value
          @nmi_armed = true
        end

        # The register bits 5 and 6 of an indexed postbyte name.
        def index_register
          case @post & 0x60
          when 0x00 then @x
          when 0x20 then @y
          when 0x40 then @u
          else @s
          end
        end

        def index_register=(value)
          case @post & 0x60
          when 0x00 then @x = value
          when 0x20 then @y = value
          when 0x40 then @u = value
          else load_s(value)
          end
        end

        # A TFR or EXG register: D, X, Y, U, S and PC are 0 to 5, A, B, CC
        # and DP 8 to 11. The other codes read as $FF or $FFFF.
        def transfer_register(code)
          case code
          when 0x0 then d
          when 0x1 then @x
          when 0x2 then @y
          when 0x3 then @u
          when 0x4 then @s
          when 0x5 then @pc
          when 0x8 then @a
          when 0x9 then @b
          when 0xa then @cc
          when 0xb then @dp
          else code < 8 ? 0xffff : 0xff
          end
        end

        def set_transfer_register(code, value)
          case code
          when 0x0 then self.d = value
          when 0x1 then @x = value
          when 0x2 then @y = value
          when 0x3 then @u = value
          when 0x4 then load_s(value)
          when 0x5 then @pc = value
          when 0x8 then @a = value
          when 0x9 then @b = value
          when 0xa then @cc = value
          when 0xb then @dp = value
          end
        end
      end
    end
  end
end
