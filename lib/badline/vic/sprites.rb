# frozen_string_literal: true

require "badline/vic/collisions"
require "badline/vic/register_log"
require "badline/vic/sprite"

module Badline
  class VIC < Cycleable
    class Sprites
      # Pixels between the start of the cycle following a write and the
      # point the new value shows. Each signal reaches the output on its own
      # path: the colors feed the final mux, the sequencer inputs — X
      # position, multicolor and expansion — sit furthest upstream, and the
      # priority mux lands one pixel ahead of them.
      COLOR_DELAY = 1
      PRIORITY_DELAY = 6
      SEQUENCER_DELAY = 7

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
        @collisions = Collisions.new(registers, width)
        @hits = @collisions.hits
        @win_color = Array.new(width, 0)
        @win_priority = Array.new(width, false)
        @palette = Array.new(4, 0)
        @log = RegisterLog.new(registers)
        @any_dma = false
        @stopped_dma = false
        @carry = Array.new(8) { [] }
        @carry_next = Array.new(8) { [] }
        @carried = false
        @lo = width
        @hi = 0
        @sequenced = -1
      end

      def [](index) = @sprites[index]

      # Pixels a sprite drew past the end of the last line land at the start
      # of this one, which is when the beam reaches them.
      def start_line
        @log.clear
        @sprites.each(&:start_line)
        @collisions.start_line
        @sequenced = -1
        @carry, @carry_next = @carry_next, @carry
        @carry_next.each(&:clear)
        @carried = @carry.any?(&:any?)
      end

      # Bauer cycles 15 and 16: MCBASE steps on for every sprite whose
      # expansion flip-flop is set, and a sprite that lands on 63 ends.
      def advance_mcbase
        @sprites.each(&:advance_mcbase) if @any_dma
      end

      # The only point a sprite's DMA stops, so the cached flag is settled
      # here and set again by the compare that starts one.
      def finish_mcbase
        @stopped_dma = false
        return unless @any_dma

        running = @sprites.count(&:displaying?)
        @sprites.each(&:finish_mcbase)
        still = @sprites.count(&:displaying?)
        @any_dma = still.positive?
        @stopped_dma = still < running
      end

      # True when the last #finish_mcbase ended a DMA, so the BA columns
      # have to be rebuilt without it.
      def stopped_dma? = @stopped_dma

      # Bauer cycle 55, ahead of the Y compare.
      def toggle_expansion
        @sprites.each(&:toggle_expansion) if @any_dma
      end

      # Run the Y/enable compare (Bauer cycles 55/56) for every sprite;
      # returns true when any sprite turned its DMA on, so the BA columns
      # can be rebuilt mid-line.
      def check_dma(line, column)
        return false if @registers[0x15].zero?

        hit = false
        @sprites.each do |sprite|
          next if sprite.displaying?

          sprite.check_dma(line, column)
          hit ||= sprite.displaying?
        end
        @any_dma ||= hit
        hit
      end

      # Not gated on the DMA flag, since this is where a display outlives its
      # DMA. MC now points at the next row, which a sprite firing after its
      # reload shows, so a line sequenced before this has to be redone.
      def check_display(line)
        @sprites.each { |sprite| sprite.check_display(line) }
        @sequenced = -1
      end

      # Not gated on the DMA flag: a row fetched at the start of the line
      # still renders when cycle 16 ends the sprite.
      def active? = @carried || @sprites.any?(&:rendering?)

      # Record a mid-line write at the pixel where it becomes visible.
      def log_change(reg, old, value, beam_x)
        delay = WRITE_DELAY[reg]
        return unless delay && active?

        @log.log(beam_x + delay, reg, old, value)
      end

      # Latch the collisions for every sprite pixel the beam has passed
      # since the last fold.
      def collide_upto(beam_x, mask)
        upto = [beam_x, @width].min
        return if upto <= @collisions.folded

        sequence_line if active?
        @collisions.fold(mask, upto, @lo, @hi)
      end

      def clear_collision(reg, beam_x) = @collisions.clear(reg, beam_x)

      # End of line: fold in the pixels the beam reached since the last
      # read, then paint the winners over the background. A line with no
      # background to paint over — one in the vertical blank — still
      # collides, so `colors` is nil there rather than absent.
      def finish_line(colors, mask)
        collide_upto(@width, mask)
        colors ? apply(colors, mask) : clear_coverage
      end

      private

      # Replay the line for every sprite, filling the per-pixel coverage
      # that both the fold and the composite read. A write logged later in
      # the line can only move pixels past it, so re-running after the log
      # grows leaves everything already folded where it was.
      def sequence_line
        return if @sequenced == @log.length

        clear_coverage
        @log.prepare
        @sprites.each do |sprite|
          sprite.sequence(@log)
          merge(sprite)
        end
        @sequenced = @log.length
      end

      # Write one sprite's pixels into the coverage, picking up the color and
      # priority registers as they stood at each pixel. The first sprite to
      # claim a pixel wins (lowest index has priority); later ones only add
      # their bit to it.
      def merge(sprite)
        bit = 1 << sprite.index
        @carry_next[sprite.index].clear
        @carry[sprite.index].each_slice(3) do |x, color, priority|
          track(x, 1)
          merge_pixel(x, color, bit, priority)
        end
        merge_run(sprite, sprite.leftmost, sprite.span, sprite.codes)
        merge_run(sprite, sprite.reload_leftmost, sprite.reload_span, sprite.reload_codes)
      end

      def merge_run(sprite, leftmost, span, codes)
        return if span.zero?

        track(leftmost, span)
        log = @log.empty? ? nil : @log
        log&.rewind
        merge_span(sprite, log, leftmost, span, codes)
      end

      def merge_span(sprite, log, leftmost, span, codes)
        bit = 1 << sprite.index
        palette = sprite.palette(log || @registers, @palette)
        priority = (log || @registers)[0x1b].anybits?(bit)
        pos = leftmost
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
          place(pos, palette[code], bit, priority) if code.nonzero?
          index += 1
          pos += 1
        end
      end

      # A pixel past the end of the line belongs to the start of the next.
      def place(pos, color, bit, priority)
        if pos < @width
          merge_pixel(pos, color, bit, priority)
        else
          @carry_next[bit.bit_length - 1].push(pos - @width, color, priority)
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

      def merge_pixel(pos, color, bit, priority)
        bits = @hits[pos]
        if bits.zero?
          @win_color[pos] = color
          @win_priority[pos] = priority
        end
        @hits[pos] = bits | bit
      end

      def apply(colors, mask)
        pos = @lo
        while pos < @hi
          if @hits[pos].nonzero?
            colors[pos] = @win_color[pos] unless @win_priority[pos] && mask[pos]
            @hits[pos] = 0
          end
          pos += 1
        end
        @lo = @width
        @hi = 0
      end

      def clear_coverage
        @hits.fill(0, @lo, @hi - @lo) if @hi > @lo
        @lo = @width
        @hi = 0
      end
    end
  end
end
