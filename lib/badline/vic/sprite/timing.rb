# frozen_string_literal: true

module Badline
  class VIC
    class Sprite
      # = Timing
      #
      # Where a region puts the sprites in the line: the cycles of their
      # fetches and of the display compare, the pixels those land on, and
      # the raster pixels the X counter reads each coordinate at. Where the
      # fetches or the compare run a cycle later than on the 6569, what
      # hangs off them moves 8 pixels with them.
      class Timing
        # The X counter's value where it steps back on a raster of more than
        # 512 pixels, to run over the eight values below it again.
        HOLD_AT = 0x188

        attr_reader :columns, :sprite_cycle, :display_off_x, :x_pixels

        def initialize(region)
          @columns = region.cycles_per_line
          @sprite_cycle = region.sprite_cycle
          @shift = region.sprite_cycle - Region::PAL.sprite_cycle
          @display_off_x = DISPLAY_OFF_X + (8 * (region.sprite_display_cycle - Region::PAL.sprite_display_cycle))
          @x_pixels = Timing.x_pixels(@columns * 8, region.x_hold)
        end

        # The column BA falls in for a sprite's own fetch: 55 for sprite 0 on
        # the 6569, and two later for each sprite after it.
        def ba_column(index) = 55 + @shift + (2 * index)

        # The raster pixel of a sprite's reload, counted from the start of
        # the line it is fetched on, so past the end of it for sprites 3-7
        # on the 6569.
        def reload_x(index) = RELOAD_X + (8 * @shift) + (RELOAD_STEP * index)

        # The X counter at a raster pixel: X_OFFSET behind it, wrapping at
        # the end of the line, less the pixels it held for from HOLD_AT on,
        # where it ran over $180-$187 a second time.
        def self.xpos(pixel, width, hold)
          count = (pixel - X_OFFSET) % width
          count < HOLD_AT ? count : count - hold
        end

        # The raster pixels at which the X counter reads each coordinate, 512
        # lists. A sprite starts at one where its X matches. On the 6569 the
        # coordinates past 503 have none.
        def self.x_pixels(width, hold)
          pixels = Array.new(512) { [] }
          width.times { |pixel| pixels[xpos(pixel, width, hold)] << pixel }
          pixels.each(&:freeze).freeze
        end
      end
    end
  end
end
