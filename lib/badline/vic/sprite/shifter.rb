# frozen_string_literal: true

module Badline
  class VIC < Cycleable
    class Sprite
      # The X comparator and the 24-bit shift register behind it: where a
      # line fires the sprite, and the pixels each firing shifts out.
      module Shifter
        EMPTY = [].freeze

        private

        # The first pixel of every comparator match along the line. Writes to
        # $d000/$d010 move the compare value mid-line, so a sprite can miss
        # its match entirely and pick up a later one, a second one, or none.
        def comparator_hits(log)
          unless log
            match = compare_x(@registers)
            return match ? [(match + 1) % @width] : EMPTY
          end

          hits = []
          log.rewind
          log.advance(0)
          from = 0
          while from < @width
            upto = [log.next_x, @width].min
            match = compare_x(log)
            hits << ((match + 1) % @width) if match && match >= from && match < upto
            break if upto >= @width

            from = upto
            log.advance(from)
          end
          hits
        end

        # The VIC's X counter only runs to 503, so the eight coordinates above
        # it never match and the sprite stays dark — the gap the spritegap
        # tests find at $1f8.
        def compare_x(view)
          msb = view[0x10].anybits?(@bit) ? 0x100 : 0
          xpos = msb | view[index * 2]
          return if xpos >= @width

          (xpos + COMPARE_OFFSET) % @width
        end

        def run(log, start, codes, bits)
          @sr = bits
          log&.rewind
          pos = start
          count = 0
          boundary = log ? 0 : Float::INFINITY
          mc = multicolor?
          expanded = x_expanded?
          while count < MAX_SPAN
            if pos >= boundary
              log.advance(pos)
              mc = log[0x1c].anybits?(@bit)
              expanded = log[0x1d].anybits?(@bit)
              boundary = log.next_x
            end
            count.zero? ? prime(mc) : step(mc, expanded)
            break if @latch.zero? && @sr.zero?

            codes[count] = @latch
            count += 1
            pos += 1
          end
          count
        end

        # The X match loads the shift register and arms both flip-flops, so
        # the sprite's first pixel comes straight off the fetched row.
        def prime(multicolor)
          @mc_flop = false
          @xe_flop = false
          @latch = (@sr >> 22) & (multicolor ? 3 : 2)
        end

        # One pixel of the sequencer. An unexpanded sprite shifts every pixel;
        # an expanded one shifts every other, and the multicolor latch reloads
        # every other shift, so its pairs stretch with the expansion. Both
        # flip-flops sit idle while their register bit is clear, which is why
        # the first pixel after a mid-sprite change repeats the last one.
        def step(multicolor, expanded)
          shift = true
          if expanded
            shift = @xe_flop
            @xe_flop = !@xe_flop
          else
            @xe_flop = false
          end
          @mc_flop = false unless multicolor
          return unless shift

          @sr = (@sr << 1) & 0xffffff
          load_latch(multicolor)
        end

        def load_latch(multicolor)
          if multicolor
            @latch = (@sr >> 22) & 3 if @mc_flop
            @mc_flop = !@mc_flop
          else
            @latch = (@sr >> 22) & 2
          end
        end
      end
    end
  end
end
