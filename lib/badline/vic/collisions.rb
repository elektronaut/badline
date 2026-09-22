# frozen_string_literal: true

module Badline
  class VIC < Cycleable
    # = Sprite collisions
    #
    # The $D01E/$D01F latches and the per-pixel sprite coverage that feeds
    # them. Collisions latch as the beam passes each covered pixel, so a
    # read mid-line sees the pixels drawn before the reading cycle and none
    # of the ones after it.
    class Collisions
      # $D019 latch bits raised by the collision registers.
      SPRITE_COLLISION_IRQ = 0x04 # IMMC, mirrors $D01E
      DATA_COLLISION_IRQ   = 0x02 # IMBC, mirrors $D01F

      # A read holds the register's reset asserted past the cycle that
      # issued it, so the pixels drawn under it never reach the register.
      # The read still reports only the pixels drawn before its own cycle,
      # which is why the two numbers do not cancel out.
      CLEAR_OVERRUN = 12

      # The pixel the last fold reached, so the sprites know whether a read
      # has anything left to latch.
      attr_reader :folded

      # One bitmask per pixel of the line, written straight by the sprite
      # merge and read back here and by the composite.
      attr_reader :hits

      def initialize(registers, width)
        @registers = registers
        @width = width
        @hits = Array.new(width, 0)
        @folded = 0
        @cleared_sprite = 0
        @cleared_data = 0
      end

      def start_line
        @folded = 0
        @cleared_sprite = carry(@cleared_sprite)
        @cleared_data = carry(@cleared_data)
      end

      # Latch every covered pixel between the last fold and the beam. The
      # sprites' touched span bounds the scan; the coverage is zero outside
      # it either way.
      def fold(mask, upto, low, high)
        from = [@folded, low].max
        @folded = upto
        scan(mask, from, [upto, high].min)
      end

      # A read resets its register for the pixels that follow the reading
      # cycle as well as for everything before it.
      def clear(reg, beam_x)
        if reg == 0x1e
          @cleared_sprite = beam_x + CLEAR_OVERRUN
        else
          @cleared_data = beam_x + CLEAR_OVERRUN
        end
      end

      private

      # Two or more sprites on a pixel collide with each other; any sprite
      # over a foreground pixel collides with the graphics. Pixels still
      # under a read's reset are dropped rather than latched.
      def scan(mask, from, upto)
        sprite_clash = 0
        data_clash = 0
        pos = from
        while pos < upto
          bits = @hits[pos]
          unless bits.zero?
            sprite_clash |= bits if pos >= @cleared_sprite && bits.anybits?(bits - 1)
            data_clash |= bits if pos >= @cleared_data && mask[pos]
          end
          pos += 1
        end
        latch(sprite_clash, data_clash)
      end

      def latch(sprite_clash, data_clash)
        latch_one(0x1e, sprite_clash, SPRITE_COLLISION_IRQ)
        latch_one(0x1f, data_clash, DATA_COLLISION_IRQ)
      end

      # The IRQ is raised on the edge out of an empty register, so a
      # collision folded on top of an unread one raises nothing.
      def latch_one(reg, clash, irq)
        return if clash.zero?
        return unless @registers.collide!(reg, clash)

        @registers.latch_irq!(irq)
      end

      # A reset still asserted at the line wrap carries into the new line.
      def carry(cleared)
        cleared > @width ? cleared - @width : 0
      end
    end
  end
end
