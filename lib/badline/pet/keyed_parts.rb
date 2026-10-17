# frozen_string_literal: true

module Badline
  class PET
    class Canvas
      # The picture in a keyed snapshot module, under `prefix`: each dot's
      # palette index, the row each four dots were last painted from, and
      # each line's span. Every line is drawn again once loaded.
      module KeyedState
        def save_fields(out, prefix)
          out.bytes("#{prefix}dots", @display).ints("#{prefix}painted", @painted)
          out.ints("#{prefix}span_from", @span_from).ints("#{prefix}span_to", @span_to)
        end

        def load_fields(input, prefix)
          input.bytes_into("#{prefix}dots", @display)
          input.ints_into("#{prefix}painted", @painted)
          input.ints_into("#{prefix}span_from", @span_from)
          input.ints_into("#{prefix}span_to", @span_to)
          @dirty_lines.fill(true)
        end
      end

      include KeyedState
    end

    class CRTCVideo
      # Where the beam is on the picture and what the frames so far have
      # framed it by, and the picture under canvas.*, in a keyed snapshot
      # module (BL-VIDEO).
      module KeyedState
        def save_fields(out)
          out.int("displayed", @displayed).int("frame_displayed", @frame_displayed).bool("line_shown", @line_shown)
          out.int("y", @y).int("from_y", @from_y).int("to_y", @to_y).int("shown_from", @shown_from)
          out.int("shown_to", @shown_to).bool("on_canvas", @on_canvas).int("origin", @origin)
          out.int("from", @from).int("to", @to)
          @canvas.save_fields(out, "canvas.")
        end

        def load_fields(input)
          @displayed = input.int("displayed", @displayed)
          @frame_displayed = input.int("frame_displayed", @frame_displayed)
          @line_shown = input.bool("line_shown", @line_shown)
          @y = input.int("y", @y)
          @from_y = input.int("from_y", @from_y)
          @to_y = input.int("to_y", @to_y)
          @shown_from = input.int("shown_from", @shown_from)
          @shown_to = input.int("shown_to", @shown_to)
          @on_canvas = input.bool("on_canvas", @on_canvas)
          @origin = input.int("origin", @origin)
          @from = input.int("from", @from)
          @to = input.int("to", @to)
          @canvas.load_fields(input, "canvas.")
        end
      end

      include KeyedState
    end

    class DiscreteVideo
      # The cycle in the line and the line in the frame, and the picture
      # under canvas.*, in a keyed snapshot module (BL-VIDEO). The row and
      # the line of the picture follow from the line on load.
      module KeyedState
        def save_fields(out)
          out.int("column", @column).int("line", @line)
          @canvas.save_fields(out, "canvas.")
        end

        def load_fields(input)
          @column = input.int("column", @column) % CYCLES_PER_LINE
          @line = input.int("line", @line) % LINES_PER_FRAME
          follow_line
          @canvas.load_fields(input, "canvas.")
        end
      end

      include KeyedState
    end

    class Bus
      class Expansion
        # The control register and the board's 64K, under `prefix`. The
        # banks are laid over the pages again once the bus is loaded.
        module KeyedState
          def save_fields(out, prefix)
            out.int("#{prefix}control", @control).bytes("#{prefix}ram", @cells)
          end

          def load_fields(input, prefix)
            @control = input.byte("#{prefix}control", @control)
            input.bytes_into("#{prefix}ram", @cells)
          end
        end

        include KeyedState
      end

      # The RAM below $8000, the screen RAM, the last byte on the bus under
      # bus.* and an 8096's board under expansion.*, in a keyed snapshot
      # module (BL-RAM). The pages are laid out again once they are loaded
      # (#restored!). The ROMs come with the model.
      module KeyedState
        def save_fields(out)
          @ram.save_fields(out, "ram")
          out.bytes("screen", @screen.cells).int("bus.data", @data)
          @expansion&.save_fields(out, "expansion.")
        end

        def load_fields(input)
          @ram.load_fields(input, "ram")
          @data = input.byte("bus.data", @data)
          input.bytes_into("screen", @screen.cells)
          @expansion&.load_fields(input, "expansion.")
        end

        def restored! = map_pages
      end

      include KeyedState
    end
  end
end
