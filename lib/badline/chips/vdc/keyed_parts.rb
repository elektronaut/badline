# frozen_string_literal: true

module Badline
  module Chips
    class VDC
      class Raster
        # The raster's fields in a keyed snapshot module, under `prefix`:
        # the frame count, where the beam is in the character rows and the
        # frame, and the frame's size and sync as it latched them.
        module KeyedState
          def save_fields(out, prefix)
            out.int("#{prefix}frame", @frame).int("#{prefix}row", @row).int("#{prefix}row_line", @row_line)
            out.bool("#{prefix}adjusting", @adjusting).int("#{prefix}frame_line", @frame_line)
            out.int("#{prefix}frame_lines", @frame_lines).int("#{prefix}sync_start", @sync_start)
            out.int("#{prefix}sync_lines", @sync_lines)
          end

          def load_fields(input, prefix)
            @frame = input.int("#{prefix}frame", @frame)
            @row = input.int("#{prefix}row", @row)
            @row_line = input.int("#{prefix}row_line", @row_line)
            @adjusting = input.bool("#{prefix}adjusting", @adjusting)
            @frame_line = input.int("#{prefix}frame_line", @frame_line)
            @frame_lines = input.int("#{prefix}frame_lines", @frame_lines)
            @sync_start = input.int("#{prefix}sync_start", @sync_start)
            @sync_lines = input.int("#{prefix}sync_lines", @sync_lines)
          end
        end

        include KeyedState
      end

      class Window
        # The start addresses the frame latched, under `prefix`.
        module KeyedState
          def save_fields(out, prefix)
            out.int("#{prefix}display_start", @display_start).int("#{prefix}attribute_start", @attribute_start)
          end

          def load_fields(input, prefix)
            @display_start = input.word("#{prefix}display_start", @display_start)
            @attribute_start = input.word("#{prefix}attribute_start", @attribute_start)
          end
        end

        include KeyedState
      end

      class Painter
        # The display's size, as the frame latched it, and the window's
        # start addresses. The picture is painted again.
        module KeyedState
          def save_fields(out)
            out.int("display.width", @width).int("display.height", @height)
            @window.save_fields(out, "window.")
          end

          def load_fields(input)
            resize(input.int("display.width", @width), input.int("display.height", @height))
            @window.load_fields(input, "window.")
          end
        end

        include KeyedState
      end

      # The VDC's fields in a keyed snapshot module (Snapshot::Keyed): the
      # registers, the RAM, the register selected, the data latches, the
      # dot clock's phase and the line's length in the same units
      # (dots·Hz, the line latched at its start), how long an access or
      # block operation stays busy from now, the raster under raster.* and
      # the display's size and window under display.* and window.*. The
      # RAM's layout comes from R28 on load.
      module KeyedState
        def save_fields(out)
          out.bytes("registers", @registers).bytes("ram", @memory.ram).int("selected", @selected)
          out.int("read_latch", @read_latch).int("write_data", @write_data).int("phase", @phase)
          out.int("line_units", @line_units).int("busy_for", @busy_until - @phase)
          @raster.save_fields(out, "raster.")
          @painter.save_fields(out)
          out
        end

        def load_fields(input)
          input.bytes_into("registers", @registers)
          input.bytes_into("ram", @memory.ram)
          @selected = input.masked("selected", @selected, 0x3f)
          @read_latch = input.byte("read_latch", @read_latch)
          @write_data = input.byte("write_data", @write_data)
          @phase = input.int("phase", @phase)
          @line_units = input.int("line_units", @line_units)
          @busy_until = @phase + input.int("busy_for", @busy_until - @phase)
          @raster.load_fields(input, "raster.")
          @painter.load_fields(input)
        end

        def restored!
          @memory.mode64 = @registers[28].anybits?(0x10)
        end
      end

      include KeyedState
    end
  end
end
