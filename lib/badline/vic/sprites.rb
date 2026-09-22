# frozen_string_literal: true

require "badline/vic/register_log"
require "badline/vic/sprite"

module Badline
  class VIC < Cycleable
    class Sprites
      # $D019 latch bits raised by the collision registers.
      SPRITE_COLLISION_IRQ = 0x04 # IMMC, mirrors $D01E
      DATA_COLLISION_IRQ   = 0x02 # IMBC, mirrors $D01F

      # Pixels between the start of the cycle following a write and the
      # point the new value shows. Each signal reaches the output on its own
      # path: the colors feed the final mux, the sequencer inputs — X
      # position, multicolor and expansion — sit furthest upstream, and the
      # priority mux lands one pixel ahead of them.
      COLOR_DELAY = 9
      PRIORITY_DELAY = 14
      SEQUENCER_DELAY = 15

      WRITE_DELAY = Array.new(2**6).tap do |delays|
        (0x00..0x0e).step(2) { |reg| delays[reg] = SEQUENCER_DELAY }
        [0x10, 0x1c, 0x1d].each { |reg| delays[reg] = SEQUENCER_DELAY }
        delays[0x1b] = PRIORITY_DELAY
        [0x25, 0x26, *0x27..0x2e].each { |reg| delays[reg] = COLOR_DELAY }
      end.freeze

      def initialize(registers, bank, width)
        @registers = registers
        @bank = bank
        @width = width
        @sprites = Array.new(8) { |i| Sprite.new(i, registers, bank, width) }
        @hits = Array.new(width, 0)
        @win_color = Array.new(width, 0)
        @win_priority = Array.new(width, false)
        @palette = Array.new(4, 0)
        @log = RegisterLog.new(registers)
        @any_dma = false
      end

      def [](index) = @sprites[index]

      def start_line
        @log.clear
        @sprites.each(&:start_line)
      end

      # Bauer cycles 15 and 16: MCBASE steps on for every sprite whose
      # expansion flip-flop is set, and a sprite that lands on 63 ends.
      def advance_mcbase
        @sprites.each(&:advance_mcbase) if @any_dma
      end

      # The only point a sprite's DMA stops, so the cached flag is settled
      # here and set again by the compare that starts one.
      def finish_mcbase
        return unless @any_dma

        @sprites.each(&:finish_mcbase)
        @any_dma = @sprites.any?(&:displaying?)
      end

      # Bauer cycle 55, ahead of the Y compare.
      def toggle_expansion
        @sprites.each(&:toggle_expansion) if @any_dma
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
        @any_dma ||= hit
        hit
      end

      def check_display(line)
        @sprites.each { |sprite| sprite.check_display(line) } if @any_dma
      end

      # Not gated on the DMA flag: a row fetched at the start of the line
      # still renders when cycle 16 ends the sprite.
      def active? = @sprites.any?(&:rendering?)

      # Record a mid-line write at the pixel where it becomes visible.
      def log_change(reg, old, value, beam_x)
        delay = WRITE_DELAY[reg]
        return unless delay && active?

        @log.log(beam_x + delay, reg, old, value)
      end

      # Sequence each displaying sprite's row, merge the results into the
      # scratch buffers, then apply the winners over the background in a
      # single pass over the touched span.
      def composite(colors, mask)
        @sprite_clash = 0
        @data_clash = 0
        @lo = @width
        @hi = 0

        @log.prepare
        @sprites.each do |sprite|
          sprite.sequence(@log)
          merge(sprite, mask)
        end

        apply(colors, mask, @lo, @hi)
        register_collisions
      end

      private

      # Write one sprite's pixels into the scratch line, picking up the
      # color and priority registers as they stood at each pixel. The first
      # sprite to claim a pixel wins (lowest index has priority); later hits
      # only accumulate collision bits.
      def merge(sprite, mask)
        span = sprite.span
        return if span.zero?

        track(sprite.leftmost, span)
        log = @log.empty? ? nil : @log
        log&.rewind
        merge_span(sprite, mask, log, span)
      end

      def merge_span(sprite, mask, log, span)
        codes = sprite.codes
        bit = 1 << sprite.index
        palette = sprite.palette(log || @registers, @palette)
        priority = (log || @registers)[0x1b].anybits?(bit)
        pos = sprite.leftmost
        boundary = log ? 0 : Float::INFINITY
        index = 0
        while index < span
          if pos >= boundary
            log.advance(pos)
            sprite.palette(log, palette)
            priority = log[0x1b].anybits?(bit)
            boundary = log.next_x
          end
          code = codes[index]
          if code.nonzero?
            x = pos < @width ? pos : pos - @width
            merge_pixel(x, palette[code], bit, priority, mask)
          end
          index += 1
          pos += 1
        end
      end

      def track(left, span)
        right = left + span
        if right > @width
          @lo = 0
          @hi = @width
        else
          @lo = left if left < @lo
          @hi = right if right > @hi
        end
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
