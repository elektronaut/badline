# frozen_string_literal: true

module Badline
  module Chips
    class VIC
      # The shape of the line batch the renderer keeps (design note §9.2).
      # A snapshot whose line.layout differs restarts the rest of its line
      # with an empty pipeline.
      LINE_LAYOUT = 1

      # The VIC-II's fields in a keyed snapshot module (Snapshot::Keyed):
      # the beam, the g-access ring oldest first under g.*, the light pen
      # and raster latches, the video matrix line, the registers, the
      # display state, the sequencer and the sprites, the line batch under
      # line.* with line.layout, and the picture as display. The IRQ line,
      # the sprites' BA columns, whether any sprite DMA runs and the
      # display's copy of the lines are worked out on load.
      module KeyedState
        def save_fields(out)
          out.int("column", @column).int("raster", @rasterline).int("fetch_d011", @fetch_d011)
          save_ring_fields(out)
          out.bool("lp_triggered", @lp_triggered).bool("lp_low", @lp_low).bool("raster_match", @raster_match)
          out.int("bank_lines", @vic_bank.lines).bytes("character_buffer", @character_buffer)
          out.bytes("color_buffer", @color_buffer)
          out.int("output_line", @output_line).bool("test_wrap", @test_wrap) if @iie
          @registers.save_fields(out)
          @display_state.save_fields(out)
          out.int("line.layout", LINE_LAYOUT)
          @sequencer.save_fields(out, "line.")
          @sprites.save_fields(out, "line.")
          out.bytes("display", @lines.flatten)
          out
        end

        def load_fields(input)
          @column = input.int("column", @column)
          @rasterline = @output_line = input.int("raster", @rasterline)
          @fetch_d011 = input.byte("fetch_d011", @fetch_d011)
          load_ring_fields(input)
          @lp_triggered = input.bool("lp_triggered", @lp_triggered)
          @lp_low = input.bool("lp_low", @lp_low)
          @raster_match = input.bool("raster_match", @raster_match)
          @vic_bank.lines = input.int("bank_lines", @vic_bank.lines)
          input.bytes_into("character_buffer", @character_buffer)
          input.bytes_into("color_buffer", @color_buffer)
          load_test_fields(input) if @iie
          @registers.load_fields(input)
          @display_state.load_fields(input)
          line = input.int("line.layout", 0) == LINE_LAYOUT
          input.adjust("line in progress from another renderer, restarted") unless line || input.missing?
          @sequencer.load_fields(input, "line.", line)
          @sprites.load_fields(input, "line.", line)
          load_display_fields(input)
        end

        def restored!
          @registers.restored!
          @sprites.restored!
          rebuild_sprite_ba
          @dirty_lines.fill(true)
        end

        private

        # Oldest first, so the ring's base is the reader's own.
        def save_ring_fields(out)
          order = Array.new(4) { |age| (@g_tick + 1 + age) & 3 }
          out.ints("g.kind", order.map { |slot| @g_kind[slot] }).ints("g.data", order.map { |slot| @g_data[slot] })
          out.ints("g.char", order.map { |slot| @g_char[slot] }).ints("g.color", order.map { |slot| @g_color[slot] })
          out.int("g.kept_char", @g_kept_char).int("g.kept_color", @g_kept_color).bool("g.display", @g_display)
        end

        def load_ring_fields(input)
          @g_tick = 3
          input.ints_into("g.kind", @g_kind)
          input.ints_into("g.data", @g_data)
          input.ints_into("g.char", @g_char)
          input.ints_into("g.color", @g_color)
          @g_kept_char = input.byte("g.kept_char", @g_kept_char)
          @g_kept_color = input.masked("g.kept_color", @g_kept_color, 0x0f)
          @g_display = input.bool("g.display", @g_display)
        end

        def load_test_fields(input)
          @output_line = input.int("output_line", @output_line)
          @test_wrap = input.bool("test_wrap", @test_wrap)
        end

        def load_display_fields(input)
          display = @lines.flatten
          input.bytes_into("display", display)
          @lines.each_with_index do |line, number|
            line.replace(display[number * @width, @width])
            @display[number * @width, @width] = line
          end
        end
      end

      include KeyedState
    end
  end
end
