# frozen_string_literal: true

module Badline
  class VIC < Cycleable
    # = Sprite
    #
    # The DMA/display state machine and the pixel sequencer for one sprite.
    # The sequencer is a 24-bit shift register clocked once per pixel: the X
    # comparator starts it, the expansion flip-flop gates the shift, and the
    # multicolor flip-flop gates a two-bit output latch that feeds the color
    # mux. Registers written mid-sprite therefore take hold from the pixel
    # they reach, rather than re-decoding the row.
    class Sprite
      X_OFFSET = 104

      # MCBASE and MC are six-bit byte counters into the sprite's 64-byte
      # block. A sprite ends when MCBASE reaches exactly 63, which is why a
      # mid-line $d017 write that steps it past 63 keeps it running.
      LAST_MCBASE = 63
      MC_MASK = 0x3f

      # The X comparator matches the pixel before the sprite's first one.
      COMPARE_OFFSET = X_OFFSET - 1

      # 24 bits at two pixels each, plus slack for a mid-sprite expansion
      # change stretching the tail.
      MAX_SPAN = 64

      # Latch codes are the multicolor bit pairs: 0 is transparent, 1 and 3
      # are the shared colors, 2 the sprite's own.
      SHARED0 = 1
      OWN_COLOR = 2
      SHARED1 = 3

      attr_reader :index, :leftmost, :span, :codes

      def initialize(index, registers, bank, width)
        @index = index
        @registers = registers
        @bank = bank
        @width = width
        @bit = 1 << index
        @dma = false
        @display_on = false
        @mcbase = 0
        @mc = 0
        @exp_ff = true
        @bits = 0
        @row_ready = false
        @codes = Array.new(MAX_SPAN, 0)
        @leftmost = 0
        @span = 0
        @sr = 0
        @latch = 0
        @mc_flop = false
        @xe_flop = false
      end

      def displaying? = @dma

      # True when this line has a fetched row waiting for the sequencer.
      def rendering? = @row_ready

      def enabled? = @registers[0x15].anybits?(@bit)
      def multicolor? = @registers[0x1c].anybits?(@bit)
      def x_expanded? = @registers[0x1d].anybits?(@bit)
      def y_expanded? = @registers[0x17].anybits?(@bit)
      def priority? = @registers[0x1b].anybits?(@bit)

      def x
        msb = @registers[0x10].anybits?(@bit) ? 0x100 : 0
        msb | @registers[index * 2]
      end

      def y = @registers[(index * 2) + 1]
      def color = @registers[0x27 + index] & 0x0f

      # Cycle 15: MCBASE takes two of the three bytes a displayed row
      # consumes, but only while the expansion flip-flop is set.
      def advance_mcbase
        hold_expansion
        @mcbase = (@mcbase + 2) & MC_MASK if @exp_ff
      end

      # Cycle 16: the third byte, then the end-of-sprite compare. MCBASE has
      # to land on 63 exactly — a crunched sprite steps over it and runs on
      # through the rest of its block.
      def finish_mcbase
        hold_expansion
        @mcbase = (@mcbase + 1) & MC_MASK if @exp_ff
        return unless @mcbase == LAST_MCBASE

        @dma = false
        @display_on = false
      end

      # Cycle 55: MxYE inverts the expansion flip-flop, ahead of the Y
      # compare that may reset it again.
      def toggle_expansion
        @exp_ff = y_expanded? ? !@exp_ff : true
      end

      # Cycles 55 and 56: a Y/enable match starts the DMA and rewinds
      # MCBASE. Display is enabled separately in cycle 58, so the rows
      # render from the following line on.
      def check_dma(line)
        return if @dma || !enabled? || line != y

        @dma = true
        @mcbase = 0
        @exp_ff = false if y_expanded?
      end

      # Cycle 58: MC is reloaded from MCBASE for the coming row, and a
      # sprite with DMA running starts (or resumes) displaying only while Y
      # still matches — a Y write between the compares keeps the data fetch
      # running invisibly.
      def check_display(line)
        @mc = @mcbase
        @display_on = true if @dma && line == y
      end

      # The row fetched at the end of the previous line renders on this one.
      def start_line
        @span = 0
        @row_ready = false
        return unless @dma && @display_on

        fetch(@mc)
        @row_ready = true
      end

      # Replay the line through the pixel sequencer, filling the code buffer
      # from the X match on. A log of mid-line register writes makes the
      # comparator and the shift register see the values each pixel was
      # drawn with.
      def sequence(log = nil)
        @span = 0
        return unless @row_ready

        log = nil if log.nil? || log.empty?
        start = trigger_x(log)
        return unless start

        @leftmost = start
        run(log, start)
      end

      # The color at a raster position, for a sprite sequenced with the
      # registers as they stand.
      def pixel(raster_x)
        dist = raster_x - @leftmost
        dist += @width if dist.negative?
        return nil if dist >= @span

        code = @codes[dist]
        return nil if code.zero?

        palette(@registers, Array.new(4, 0))[code]
      end

      # Fill a four-entry lookup from latch code to color, against a view of
      # the color registers.
      def palette(view, into)
        into[SHARED0] = view[0x25] & 0x0f
        into[OWN_COLOR] = view[0x27 + index] & 0x0f
        into[SHARED1] = view[0x26] & 0x0f
        into
      end

      private

      # The first pixel at which the comparator sees its own X coordinate.
      # Writes to $d000/$d010 move the compare value mid-line, so a sprite
      # can miss its match entirely and pick up a later one — or none.
      def trigger_x(log)
        unless log
          match = compare_x(@registers)
          return match && ((match + 1) % @width)
        end

        log.rewind
        log.advance(0)
        from = 0
        while from < @width
          upto = [log.next_x, @width].min
          match = compare_x(log)
          return (match + 1) % @width if match && match >= from && match < upto
          break if upto >= @width

          from = upto
          log.advance(from)
        end
        nil
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

      def run(log, start)
        @sr = @bits
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

          @codes[count] = @latch
          count += 1
          pos += 1
        end
        @span = count
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
        reload(multicolor)
      end

      def reload(multicolor)
        if multicolor
          @latch = (@sr >> 22) & 3 if @mc_flop
          @mc_flop = !@mc_flop
        else
          @latch = (@sr >> 22) & 2
        end
      end

      # Bauer §3.8 rule 1: the flip-flop is held set while MxYE is clear,
      # so an unexpanded sprite advances a row every line.
      def hold_expansion
        @exp_ff = true unless y_expanded?
      end

      # The three s-accesses step MC through the sprite's block, wrapping
      # within it.
      def fetch(counter)
        base = pointer * 64
        @bits = (@bank.peek(base + counter) << 16) |
                (@bank.peek(base + ((counter + 1) & MC_MASK)) << 8) |
                @bank.peek(base + ((counter + 2) & MC_MASK))
      end

      def pointer = @bank.peek(@registers.screen_base + 0x3f8 + index)
    end
  end
end
