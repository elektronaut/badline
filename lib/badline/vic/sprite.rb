# frozen_string_literal: true

require "badline/vic/sprite/shifter"

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

      # The s-accesses reload the shift register partway through the line,
      # at raster pixel 459 for sprite 0 and 16 later for each sprite after
      # it. A sprite still shifting there loses the rest of its row (the
      # output holds for that one pixel), and the comparator is ignored for
      # the twelve pixels from it. Decoded from the spritescan dump.
      RELOAD_X = 459
      RELOAD_STEP = 16
      RELOAD_DEAD = 12

      # On the line of its last row, a sprite whose DMA ended at cycle 16
      # loses its display at cycle 58, so no hit from this pixel on starts
      # it (spritegap3). One already shifting runs on.
      DISPLAY_OFF_X = 460

      include Shifter

      attr_reader :index, :leftmost, :span, :codes,
                  :reload_leftmost, :reload_span, :reload_codes

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
        @reload_codes = Array.new(MAX_SPAN, 0)
        @reload_leftmost = 0
        @reload_span = 0
        @reload_x = (RELOAD_X + (RELOAD_STEP * index)) % width
        @reload_next_line = RELOAD_X + (RELOAD_STEP * index) < width
        @sr = 0
        @latch = 0
        @mc_flop = false
        @xe_flop = false
        @first_byte_lost = false
      end

      def displaying? = @dma

      # True when this line has a row for the sequencer: its own, the next
      # one for a sprite that reloads late in the line, or the last one for
      # a sprite that reloads at its start.
      def rendering?
        return true if @row_ready

        @reload_next_line ? @dma && @display_on : !@prev_bits.nil?
      end

      def enabled? = @registers[0x15].anybits?(@bit)
      def multicolor? = @registers[0x1c].anybits?(@bit)
      def x_expanded? = @registers[0x1d].anybits?(@bit)
      def y_expanded? = @registers[0x17].anybits?(@bit)
      def priority? = @registers[0x1b].anybits?(@bit)

      def x
        msb = @registers[0x10].anybits?(@bit) ? 0x100 : 0
        msb | @registers[index * 2]
      end

      # The Y comparator is eight bits wide, so the PAL lines above 255
      # match the coordinates 0-55 a second time (spritey).
      def y_match?(line) = (line & 0xff) == @registers[(index * 2) + 1]

      def color = @registers[0x27 + index] & 0x0f

      # Cycle 15: MCBASE takes two of the three bytes a displayed row
      # consumes, but only while the expansion flip-flop is set.
      def advance_mcbase
        hold_expansion
        @mcbase = (@mcbase + 2) & MC_MASK if @exp_ff
      end

      # Cycle 16: the third byte, then the end-of-sprite compare. MCBASE has
      # to land on 63 exactly — a crunched sprite steps over it and runs on
      # through the rest of its block. Only the DMA stops here; the display
      # waits for cycle 58.
      def finish_mcbase
        hold_expansion
        @mcbase = (@mcbase + 1) & MC_MASK if @exp_ff
        @dma = false if @mcbase == LAST_MCBASE
      end

      # Cycle 55: MxYE inverts the expansion flip-flop, ahead of the Y
      # compare that may reset it again.
      def toggle_expansion
        @exp_ff = y_expanded? ? !@exp_ff : true
      end

      # Cycles 55 and 56: a Y/enable match starts the DMA and rewinds
      # MCBASE. Display is enabled separately in cycle 58, so the rows
      # render from the following line on.
      #
      # On the VIC's side, BA falls at the sprite's own column — 55 for
      # sprite 0, two later for each sprite after it, a column behind the
      # window the CPU sees in VIC::SPRITE_BA_WINDOWS — or two columns after
      # this compare, whichever is later. AEC follows three columns on, and
      # the first of the three s-accesses runs in the column it arrives in:
      # a DMA starting on the second compare therefore loses that access for
      # sprite 0, alone among the eight in following the compares
      # immediately (spriteenable2).
      def check_dma(line, column)
        return if @dma || !enabled? || !y_match?(line)

        @first_byte_lost = column + 2 > 55 + (2 * index)
        @dma = true
        @mcbase = 0
        @exp_ff = false if y_expanded?
      end

      # Cycle 58: MC is reloaded from MCBASE for the coming row, and a
      # sprite with DMA running starts displaying only while MxE and Y still
      # match — a write to either between the compares and here keeps the
      # data fetch running invisibly. The display goes off only here, and
      # only once the DMA has, so a DMA restarted on the line of its last
      # row keeps a display that was already on (spriterestart).
      def check_display(line)
        @mc = @mcbase
        if @dma
          @display_on = true if enabled? && y_match?(line)
        else
          @display_on = false
        end
      end

      # The row fetched at the end of the previous line renders on this one.
      # A lost first s-access reads back the $ff the CPU is still driving.
      def start_line
        @span = 0
        @reload_span = 0
        @prev_bits = (@bits if @row_ready && @dma)
        @row_ready = false
        lost = @first_byte_lost
        @first_byte_lost = false
        return unless @dma && @display_on

        @bits = row_bits(@mc)
        @bits |= 0xff << 16 if lost
        @row_ready = true
      end

      # Replay the line through the pixel sequencer, filling the code buffer
      # from the X match on. A log of mid-line register writes makes the
      # comparator and the shift register see the values each pixel was
      # drawn with.
      #
      # The row can be shown once before the reload and once after it, so a
      # sprite moved past the beam can fire a second time on the same line
      # (spritex). A match inside the dead pixels shows nothing.
      def sequence(log = nil)
        @span = 0
        @reload_span = 0
        reload_bits = reload_row
        return unless @row_ready || @prev_bits || reload_bits

        log = nil if log.nil? || log.empty?
        @stop_x = @dma ? nil : DISPLAY_OFF_X
        comparator_hits(log).each { |start| sequence_hit(log, start, reload_bits) }
      end

      # The color at a raster position, for a sprite sequenced with the
      # registers as they stand.
      def pixel(raster_x)
        code = code_at(raster_x, @leftmost, @span, @codes) ||
               code_at(raster_x, @reload_leftmost, @reload_span, @reload_codes)
        return nil if code.nil? || code.zero?

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

      def code_at(raster_x, leftmost, span, codes)
        dist = raster_x - leftmost
        dist += @width if dist.negative?
        codes[dist] if dist < span
      end

      def sequence_hit(log, start, reload_bits)
        return if @stop_x && start >= @stop_x

        if start < @reload_x
          sequence_early(log, start)
        elsif start >= @reload_x + RELOAD_DEAD
          sequence_reloaded(log, start, reload_bits)
        end
      end

      def sequence_early(log, start)
        bits = early_row
        return unless bits && @span.zero?

        @leftmost = start
        @span = cut_at_reload(start, run(log, start, @codes, bits), @codes)
      end

      def sequence_reloaded(log, start, bits)
        return unless bits && @reload_span.zero?

        @reload_leftmost = start
        @reload_span = cut_at_reload(start, run(log, start, @reload_codes, bits), @reload_codes)
      end

      # The row in the shift register ahead of the reload: this line's for
      # sprites 0-2, and for the others the one their reload at the start of
      # the last line brought in.
      def early_row = @reload_next_line ? current_row : @prev_bits

      def current_row = (@bits if @row_ready)

      # The row the reload brings in. Sprites 0-2 reload late in the line
      # with the next line's row, so one that fires after it shows that row
      # a line early (spritegap); the others reload at the start of the line
      # with the row it already has.
      def reload_row
        return current_row unless @reload_next_line
        return unless @dma && @display_on

        bits = row_bits(@mc)
        bits |= 0xff << 16 if @first_byte_lost
        bits
      end

      # A run that reaches the next reload is cut there, holding its last
      # pixel for one more. Returns the span that is left.
      def cut_at_reload(start, span, codes)
        reload = start < @reload_x ? @reload_x : @reload_x + @width
        cut = reload - start
        return span if cut > span || cut >= MAX_SPAN

        codes[cut] = codes[cut - 1]
        cut + 1
      end

      # Bauer §3.8 rule 1: the flip-flop is held set while MxYE is clear,
      # so an unexpanded sprite advances a row every line.
      def hold_expansion
        @exp_ff = true unless y_expanded?
      end

      # The three s-accesses step MC through the sprite's block, wrapping
      # within it.
      def row_bits(counter)
        base = pointer * 64
        (@bank.peek(base + counter) << 16) |
          (@bank.peek(base + ((counter + 1) & MC_MASK)) << 8) |
          @bank.peek(base + ((counter + 2) & MC_MASK))
      end

      def pointer = @bank.peek(@registers.screen_base + 0x3f8 + index)
    end
  end
end
