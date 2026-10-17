# frozen_string_literal: true

module Badline
  module Chips
    class CRTC
      # The CRTC's fields in a keyed snapshot module (Snapshot::Keyed): the
      # registers, the one selected, and the counters: the character, the
      # characters since horizontal sync, the line, the row, the lines of
      # vertical sync left, whether the frame is in its vertical adjust,
      # whether the row and the character show, and the memory address with
      # the row's start. The output restores its own state.
      module KeyedState
        def save_fields(out)
          out.bytes("registers", @registers).int("selected", @selected).int("column", @column)
          out.int("since_hsync", @since_hsync).int("line", @line).int("row", @row).int("vsync_lines", @vsync_lines)
          out.bool("adjusting", @adjusting).bool("row_display", @row_display).bool("column_display", @column_display)
          out.int("row_start", @row_start).int("address", @address)
        end

        def load_fields(input)
          input.bytes_into("registers", @registers)
          MASKS.each_with_index { |mask, index| @registers[index] &= mask }
          @selected = input.masked("selected", @selected, 0x1f)
          @column = input.byte("column", @column)
          @since_hsync = input.int("since_hsync", @since_hsync)
          @line = input.masked("line", @line, 0x1f)
          @row = input.masked("row", @row, 0x7f)
          @vsync_lines = input.int("vsync_lines", @vsync_lines)
          load_flag_fields(input)
          @row_start = input.masked("row_start", @row_start, 0x3fff)
          @address = input.masked("address", @address, 0x3fff)
        end

        private

        def load_flag_fields(input)
          @adjusting = input.bool("adjusting", @adjusting)
          @row_display = input.bool("row_display", @row_display)
          @column_display = input.bool("column_display", @column_display)
        end
      end

      include KeyedState
    end
  end
end
