# frozen_string_literal: true

module Badline
  module Chips
    class TED
      # What the TED reads for the picture, a single clock cycle at a time,
      # and the counters that say where it reads.
      #
      # The two DMA lines of a character row (Beam) fetch a byte a cycle
      # in phi2, in the 40 cycles of the character window, columns 54-56
      # and 0-36: the attributes on the line before the row, from the video
      # matrix base ($FF14 bits 3-7) with A10 clear, and the character
      # pointers on the row's first line, with A10 set (the datasheet's
      # video matrix and attribute addresses). The attributes go to a
      # buffer of their own, and each takes hold as its character's
      # pointer is fetched, so the row before shows its own colours to its
      # last line, as xplus4 shows them.
      #
      # On every line of a row, from the cycle after each pointer's, the
      # TED fetches the character's pattern byte in phi1, columns 55-56
      # and 0-37: from the character base ($FF13 bits 2-7) with the
      # pointer and the row's line counter, or from the bitmap base ($FF12
      # bits 3-5) with the character position and the line counter in
      # bitmap mode. With $FF07 bit 7 clear the pointer's bit 7 asks for
      # reverse and the character base supplies A10; extended colour mode
      # forces A9 and A10 low. The byte stays on the bus, where a read of
      # an address nothing answers finds it (Plus/4 openio's outrun2).
      #
      # The matrix fetches see ROM or RAM as the CPU does at $8000-$FFFF,
      # and the pattern fetches ROM with $FF12 bit 2 set or RAM with it
      # clear (Plus4::Bus#ted_fetch and #ted_pattern_fetch).
      #
      # The counters: the character position reload ($FF1A-$FF1B), the
      # character position the row starts at, which steps by 40 at the end
      # of a row's eighth line, at horizontal count 290; and the vertical
      # sub-address ($FF1F bits 0-2), the row's line, which steps with the
      # line count on the display window's lines once the frame's first
      # row is under way, wrapping from 7 to 0 whatever the DMA lines do.
      # The attribute line reads the row the reload points to after its
      # own latch: 40 on from it on a row's eighth line, the reload itself
      # otherwise. The pointer line is the line after an attribute line. A
      # frame starts with both counters at 0 and no row under way, and the
      # frame's first pointer line puts a row under way to the end of the
      # frame. The display window's lines with a row under way and the
      # display on fetch pattern bytes.
      module Fetches
        # The first and last cycles of the pattern fetches.
        PATTERN_COLUMN = 55
        PATTERN_END_COLUMN = 37

        # The cycle that latches the next row's character position.
        LATCH_COLUMN = 36

        # The cycle that counts the blink counter, horizontal count 336.
        BLINK_COLUMN = 42

        CHARACTERS = 40

        # The pattern bytes, pointers and attributes of the characters on
        # the line being fetched.
        attr_reader :patterns, :pointers, :attributes

        # The character position reload, the row's line, and whether a row
        # is under way.
        attr_reader :char_position, :row_line, :row_active

        # The bus the TED fetches from, the machine's.
        def connect(bus)
          @bus = bus
        end

        private

        def reset_fetches
          @patterns = Array.new(CHARACTERS, 0)
          @pointers = Array.new(CHARACTERS, 0)
          @attributes = Array.new(CHARACTERS, 0)
          @fetched_attributes = Array.new(CHARACTERS, 0)
          @char_position = 0
          @line_position = 0
          @row_line = 0
          @row_active = false
          @dma_kind = Beam::NO_DMA
          @pattern_fetches = false
        end

        # The fetches and counters of the cycle in +column+.
        def fetch(column)
          if column <= Beam::DMA_END_COLUMN || column >= Beam::DMA_COLUMN
            window_fetch(column)
          elsif column == PATTERN_END_COLUMN
            pattern_fetch(column) if @pattern_fetches
          elsif column == Beam::BA_COLUMN
            start_line_fetches
          elsif column == BLINK_COLUMN
            count_blink
          end
        end

        # A cycle of the character window.
        def window_fetch(column)
          dma_fetch(column) unless @dma_kind == Beam::NO_DMA
          pattern_fetch(column) if @pattern_fetches && column != Beam::DMA_COLUMN
          latch_char_position if column == LATCH_COLUMN
        end

        # The blink counter counts a frame on one line of the vertical
        # blank, the line xplus4 counts it on.
        def count_blink
          return unless @line == (lines_per_frame == 312 ? 256 : 228)

          @blink = (@blink + 1) & 0x0f
          blink_carry if @blink.zero?
        end

        # Column 51: what the line fetches, decided where BA is.
        def start_line_fetches
          @dma_kind = dma_kind
          @row_active = true if @dma_kind == Beam::POINTER_DMA
          @line_position = @char_position
          @pattern_fetches = @row_active && @line <= Beam::LAST_DISPLAY_LINE && display_enabled? && !@bus.nil?
        end

        # The attributes on a line whose low three bits match $FF06's
        # scroll, below line 203, and the pointers on the line after one
        # that fetched attributes (the datasheet's DMA timing, step 8),
        # whatever the scroll says by then.
        def dma_kind
          return Beam::NO_DMA unless display_enabled?
          return Beam::POINTER_DMA if @dma_kind == Beam::ATTRIBUTE_DMA
          return Beam::NO_DMA unless @line < Beam::LAST_DISPLAY_LINE

          (@line - @registers[0x06]).nobits?(0x07) ? Beam::ATTRIBUTE_DMA : Beam::NO_DMA
        end

        def display_enabled? = @registers[0x06].anybits?(0x10)

        def dma_fetch(column)
          bus = @bus
          return if bus.nil?

          index = column >= Beam::DMA_COLUMN ? column - Beam::DMA_COLUMN : column + (Beam::CYCLES_PER_LINE - Beam::DMA_COLUMN)
          matrix = (@registers[0x14] & 0xf8) << 8
          if @dma_kind == Beam::ATTRIBUTE_DMA
            position = latching? ? @char_position + CHARACTERS : @char_position
            @fetched_attributes[index] = bus.ted_fetch(matrix | ((position + index) & 0x3ff))
          else
            @pointers[index] = bus.ted_fetch(matrix | 0x400 | ((@char_position + index) & 0x3ff))
            @attributes[index] = @fetched_attributes[index]
          end
        end

        def pattern_fetch(column)
          index = column >= PATTERN_COLUMN ? column - PATTERN_COLUMN : column + (Beam::CYCLES_PER_LINE - PATTERN_COLUMN)
          @patterns[index] = @bus.ted_pattern_fetch(pattern_address(index), @registers[0x12].anybits?(0x04))
        end

        def pattern_address(index)
          return bitmap_address(index) if @registers[0x06].anybits?(0x20)

          pointer = @pointers[index]
          base = @registers[0x13] & 0xf8
          if @registers[0x06].anybits?(0x40)
            pointer &= 0x3f
          elsif !@registers[0x07].anybits?(0x80)
            pointer = (pointer & 0x7f) | ((@registers[0x13] & 0x04) << 5)
          end
          (base << 8) | (pointer << 3) | @row_line
        end

        def bitmap_address(index)
          ((@registers[0x12] & 0x38) << 10) | (((@line_position + index) & 0x3ff) << 3) | @row_line
        end

        # The end of a row's eighth line moves the reload on to the next
        # row.
        def latch_char_position
          @char_position = (@char_position + CHARACTERS) & 0x3ff if latching?
        end

        # Whether the line ends a row, and latches the next row's position.
        def latching? = @row_active && @row_line == 7 && @line <= Beam::LAST_DISPLAY_LINE

        # The line count steps to +line+: the row's next line, up to the
        # last line of the display window.
        def step_row_line(line)
          @row_line = (@row_line + 1) & 0x07 if @row_active && line <= Beam::LAST_DISPLAY_LINE
        end

        # The end of the frame.
        def end_fetch_frame
          @char_position = 0
          @row_line = 0
          @row_active = false
        end
      end
    end
  end
end
