# frozen_string_literal: true

module Badline
  class C128
    class VDC
      # The VDC's raster: R0 + 1 characters a line, R9 + 1 lines a row,
      # R4 + 1 rows a frame and then R5 more lines, with the frame's size
      # and sync taken as it begins. Each line ends into the Painter while
      # the VDC renders. Interlace, R8, is left out.
      class Raster
        attr_reader :frame, :frame_lines, :sync_lines

        def initialize(registers, painter)
          @registers = registers
          @painter = painter
          reset!
        end

        def reset!
          @frame = 0
          begin_frame
        end

        # The dots of a line, at least Painter::MIN_LINE_DOTS.
        def line_dots
          dots = (@registers[0] + 1) * VDC.char_dots(@registers)
          [dots, Painter::MIN_LINE_DOTS].max
        end

        # Outside the displayed rows, as status bit 5 reads.
        def vertical_blank? = @adjusting || @row >= @registers[6]

        def end_line(render)
          paint_line if render
          @frame_line += 1
          @row_line += 1
          if @adjusting
            begin_frame(next_frame: true) if @row_line >= (@registers[5] & 0x1f)
          elsif @row_line > (@registers[9] & 0x1f)
            @row_line = 0
            @row += 1
            end_rows if @row > @registers[4]
          end
        end

        private

        def paint_line
          sync = @frame_line >= @sync_start && @frame_line < @sync_start + @sync_lines
          line_y = (@frame_line - @sync_start - @sync_lines) % @frame_lines
          @painter.paint(line_y, @adjusting ? -1 : @row, @row_line, sync, @frame)
        end

        def end_rows
          return begin_frame(next_frame: true) if @registers[5].nobits?(0x1f)

          @adjusting = true
          @row_line = 0
        end

        # The vertical sync starts R7 - 1 rows in, as the Programmer's
        # Reference Guide counts R7 "plus 1", and lasts R3 bits 4-7 lines,
        # or 16 for 0.
        def begin_frame(next_frame: false)
          regs = @registers
          @frame += 1 if next_frame
          @row = 0
          @row_line = 0
          @adjusting = false
          @frame_line = 0
          row_lines = (regs[9] & 0x1f) + 1
          @frame_lines = ((regs[4] + 1) * row_lines) + (regs[5] & 0x1f)
          @sync_start = ((regs[7] - 1) % (regs[4] + 1)) * row_lines
          @sync_lines = regs[3] >> 4
          @sync_lines = 16 if @sync_lines.zero?
          @painter.begin_frame(line_dots, @frame_lines)
        end
      end
    end
  end
end
