# frozen_string_literal: true

module Badline
  class VIC
    # The VIC's state for a snapshot.
    module SavedState
      # Everything the VIC holds between cycles: the beam, the fetch and
      # g-access pipeline, the light pen and raster latches, the finished
      # lines, on the VIC-IIe the display line and the TEST bit's wrap, the
      # registers and the display, sequencer and sprite logic.
      # Whether it renders is the host's, and every line comes back dirty so
      # a front end repaints.
      def save_state(out)
        out.marker("VIC")
        out.int(@column).int(@rasterline)
        out.int(@g_tick).ints(@g_kind).int(@g_kept_char).int(@g_kept_color).boolean(@g_display)
        out.int(@fetch_d011).boolean(@lp_triggered).boolean(@lp_low).boolean(@raster_match)
        out.int(@vic_bank.lines)
        out.blob(@character_buffer).blob(@color_buffer).booleans(@sprite_ba)
        @lines.each { |line| out.blob(line) }
        out.int(@output_line).boolean(@test_wrap) if @iie
        @registers.save_state(out)
        @display_state.save_state(out)
        @sequencer.save_state(out)
        @sprites.save_state(out)
      end

      def load_state(input)
        input.marker("VIC")
        load_beam(input)
        load_buffers(input)
        load_lines(input)
        load_test_state(input) if @iie
        @registers.load_state(input)
        @display_state.load_state(input)
        @sequencer.load_state(input)
        @sprites.load_state(input)
      end

      private

      def load_beam(input)
        @column = input.int
        @rasterline = @output_line = input.int
        @g_tick = input.int
        input.ints_into(@g_kind)
        @g_kept_char = input.int
        @g_kept_color = input.int
        @g_display = input.boolean?
        @fetch_d011 = input.int
        @lp_triggered = input.boolean?
        @lp_low = input.boolean?
        @raster_match = input.boolean?
        @vic_bank.lines = input.int
      end

      def load_buffers(input)
        input.blob_into(@character_buffer)
        input.blob_into(@color_buffer)
        input.booleans_into(@sprite_ba)
      end

      # The VIC-IIe's display line and TEST wrap, which only its TEST bit
      # moves off the raster line.
      def load_test_state(input)
        @output_line = input.int
        @test_wrap = input.boolean?
      end

      # The display is the finished lines one after another.
      def load_lines(input)
        @lines.each_with_index do |line, number|
          input.blob_into(line)
          @display[number * @width, @width] = line
        end
        @dirty_lines.fill(true)
      end
    end
  end
end
