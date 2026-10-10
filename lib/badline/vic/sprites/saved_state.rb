# frozen_string_literal: true

module Badline
  class VIC
    class Sprites
      # The sprites' save_state and load_state.
      module SavedState
        # Whether any sprite's DMA runs, set after Sprite#restore_counters.
        def update_any_dma
          @any_dma = @sprites.any?(&:displaying?)
        end

        # The sprites, their shared bus, the collisions and the register log,
        # then the line's coverage and the pixels carried into the next line,
        # each as x, colour and priority.
        def save_state(out)
          out.boolean(@any_dma).boolean(@stopped_dma).boolean(@carried).int(@lo).int(@hi).int(@sequenced)
          out.blob(@win_color).booleans(@win_priority).ints(@palette)
          [@carry, @carry_next].each { |carry| carry.each { |pixels| save_carry(pixels, out) } }
          @sprites.each { |sprite| sprite.save_state(out) }
          @bus.save_state(out)
          @collisions.save_state(out)
          @log.save_state(out)
        end

        def load_state(input)
          @any_dma = input.boolean?
          @stopped_dma = input.boolean?
          @carried = input.boolean?
          @lo = input.int
          @hi = input.int
          @sequenced = input.int
          input.blob_into(@win_color)
          input.booleans_into(@win_priority)
          input.ints_into(@palette)
          [@carry, @carry_next].each { |carry| carry.each { |pixels| load_carry(pixels, input) } }
          @sprites.each { |sprite| sprite.load_state(input) }
          @bus.load_state(input)
          @collisions.load_state(input)
          @log.load_state(input)
        end

        private

        def save_carry(pixels, out)
          out.int(pixels.length / 3)
          pixels.each_slice(3) { |x, color, priority| out.int(x).int(color).boolean(priority) }
        end

        def load_carry(pixels, input)
          pixels.clear
          input.int.times { pixels.push(input.int, input.int, input.boolean?) }
        end
      end
    end
  end
end
