# frozen_string_literal: true

require "badline/vic/sprite"

module Badline
  class VIC < Cycleable
    class Sprites
      # $D019 latch bits raised by the collision registers.
      SPRITE_COLLISION_IRQ = 0x04 # IMMC, mirrors $D01E
      DATA_COLLISION_IRQ   = 0x02 # IMBC, mirrors $D01F

      # Sprite registers whose mid-line writes change the rendered output
      # directly. These are priority, multicolor mode and the color
      # registers. The trigger-driven registers (X position, enable,
      # expansion) latch their effect elsewhere and keep line-start
      # semantics.
      COMPOSITE_REGS = Array.new(64, false).tap do |regs|
        [0x1b, 0x1c, 0x25, 0x26].each { |reg| regs[reg] = true }
        (0x27..0x2e).each { |reg| regs[reg] = true }
      end.freeze

      # A mid-line write becomes visible this many pixels after the start of
      # the cycle following the write. The sprite output pipeline runs one
      # cycle behind the graphics sequencer, plus the 1-pixel visibility
      # delay shared with the background registers.
      WRITE_DELAY = 9

      # Register state at a point within the line. Logged old values overlay
      # the live registers, and advance as compositing crosses each change.
      class View
        def initialize(registers)
          @registers = registers
          @overlay = {}
        end

        def [](reg)
          @overlay.fetch(reg) { @registers[reg] }
        end

        def seed(reg, value)
          @overlay[reg] = value unless @overlay.key?(reg)
        end

        def advance(reg, value)
          @overlay[reg] = value
        end
      end

      def initialize(registers, bank, width)
        @registers = registers
        @bank = bank
        @width = width
        @sprites = Array.new(8) { |i| Sprite.new(i, registers, bank, width) }
        @hits = Array.new(width, 0)
        @win_color = Array.new(width, 0)
        @win_priority = Array.new(width, false)
        @changes = []
      end

      def [](index) = @sprites[index]

      def start_line
        @changes.clear
        @sprites.each(&:start_line)
      end

      # Run the Y/enable compare (Bauer cycles 55/56) for every sprite;
      # returns true when any sprite turned its DMA on, so the BA columns
      # can be rebuilt mid-line.
      def check_dma(line)
        return false if @registers[0x15].zero?

        hit = false
        @sprites.each do |sprite|
          next if sprite.displaying?

          sprite.check_dma(line)
          hit ||= sprite.displaying?
        end
        hit
      end

      def check_display(line)
        @sprites.each { |sprite| sprite.check_display(line) }
      end

      def active? = @sprites.any?(&:displaying?)

      # Record a mid-line write to an output register at its visible pixel
      # position, for segmented compositing at the end of the line.
      def log_change(reg, old, value, beam_x)
        return unless COMPOSITE_REGS[reg] && active?

        @changes << [beam_x + WRITE_DELAY, reg, old, value]
      end

      # Merge each displaying sprite's line into the scratch buffers, then
      # apply the winners over the background in a single pass over the
      # touched span.
      def composite(colors, mask)
        @sprite_clash = 0
        @data_clash = 0
        @lo = @width
        @hi = 0

        if @changes.empty?
          merge_all(mask, 0, @width, @registers)
        else
          composite_segments(mask)
        end

        apply(colors, mask, @lo, @hi)
        register_collisions
      end

      private

      # Composite in segments between the logged register changes: the line
      # buffers hold the line-start decode, and each crossed change advances
      # the view and re-decodes the sprites it affects.
      def composite_segments(mask)
        view = seed_view
        from = 0
        @changes.each do |(beam_x, reg, _old, value)|
          merge_all(mask, from, beam_x, view) if beam_x > from
          from = beam_x if beam_x > from
          view.advance(reg, value)
          redecode(reg, view)
        end
        merge_all(mask, from, @width, view)
      end

      # Line-start state: the first logged old value per register.
      def seed_view
        View.new(@registers).tap do |view|
          @changes.each { |(_beam_x, reg, old, _value)| view.seed(reg, old) }
        end
      end

      def redecode(reg, view)
        if reg >= 0x27
          sprite = @sprites[reg - 0x27]
          sprite.redecode(view) if sprite.line_pixels
        else
          @sprites.each { |sprite| sprite.redecode(view) if sprite.line_pixels }
        end
      end

      def merge_all(mask, from, upto, view)
        @sprites.each do |sprite|
          next unless sprite.line_pixels

          seg_lo, seg_hi = merge(sprite, mask, from, upto, view)
          @lo = seg_lo if seg_lo < @lo
          @hi = seg_hi if seg_hi > @hi
        end
      end

      # Write one sprite's pixels within [from, upto) into the scratch line.
      # The first sprite to claim a pixel wins (lowest index has priority);
      # later hits only accumulate collision bits.
      def merge(sprite, mask, from, upto, view)
        left = sprite.leftmost
        pixels = sprite.line_pixels
        last = sprite.pixel_width
        bit = 1 << sprite.index
        priority = sprite.priority?(view)

        i = 0
        while i < last
          color = pixels[i]
          if color
            x = left + i
            x -= @width if x >= @width
            merge_pixel(x, color, bit, priority, mask) if x >= from && x < upto
          end
          i += 1
        end

        right = left + last
        right > @width ? [0, @width] : [left, right]
      end

      def merge_pixel(pos, color, bit, priority, mask)
        bits = @hits[pos]
        if bits.zero?
          @win_color[pos] = color
          @win_priority[pos] = priority
        else
          @sprite_clash |= bits | bit
        end
        @hits[pos] = bits | bit
        @data_clash |= bit if mask[pos]
      end

      def apply(colors, mask, from, upto)
        pos = from
        while pos < upto
          if @hits[pos].nonzero?
            colors[pos] = @win_color[pos] unless @win_priority[pos] && mask[pos]
            @hits[pos] = 0
          end
          pos += 1
        end
      end

      def register_collisions
        if @sprite_clash.nonzero? && @registers.collide!(0x1e, @sprite_clash)
          @registers.latch_irq!(SPRITE_COLLISION_IRQ)
        end
        return if @data_clash.zero?
        return unless @registers.collide!(0x1f, @data_clash)

        @registers.latch_irq!(DATA_COLLISION_IRQ)
      end
    end
  end
end
