# frozen_string_literal: true

module Badline
  module Snapshot
    module Vice
      module Vic20
        # The VIC-I as xvic 3.10 saves it, VIC-I 0.4. The layout was inferred
        # from xvic's snapshots of known states, set from its monitor and
        # stepped an instruction at a time, against what its monitor's io
        # command and its registers showed:
        #
        # - $00 dword: 1 while the frame is interlaced, $04 dword: the field,
        #   0 the long one and 1 the short one; $08 qword: the clock at the
        #   frame's first cycle
        # - $10 byte: the cycle in the line; $11 word: the raster line; $13
        #   byte: the text window, 0 before it, 1 on its first line until
        #   the column in $9000, 2 on its lines after that and 3 after it;
        #   $15 byte: the line's fetches, 0 off the window or before the
        #   column in $9000, 1 from there, 2 from the cycle before the first
        #   fetch, then 3 with a pattern fetch next and 2 with a code fetch
        #   next, 4 once done; $17 word: the line again
        # - $1B dword: the columns; $1F dword: the rows; $23 dword: the
        #   columns again; $27 dword: 0 on a line after one of the
        #   window's, 1 on the others; $2B dword: the video matrix
        #   offset the text row starts at; $33 dword: the text rows done;
        #   $37 dword: while the fetches wait, the cycles left until the
        #   cycle before the first, then the characters fetched, and the
        #   columns while $15 is 0
        # - $3D and $41 dwords: the light pen's latch, $9006 and $9007;
        #   $45 dword: 1 in every snapshot xvic wrote; $49: 8 bytes of $FF;
        #   $51 byte: the last character code fetched
        # - $52: the colour RAM, 1,024 bytes; $452: the registers, 16
        #   bytes, with $9003 bit 7 and $9004 as written; $462 dword: the
        #   raster line again
        # - $466 dword: the width of xvic's picture, $46A dword: its lines,
        #   312 on the 6561 and 262 on the 6560; $46E dword: its pitch,
        #   then the picture itself, twice its lines and 8 more of pitch
        #   bytes, and 4 bytes after it, 0 in every snapshot
        #
        # Bytes the layout leaves out, $14, $16, $19-$1A, $2F-$32 and
        # $3B-$3C, were 0 in every snapshot.
        #
        # Written: all of it from badline's VIC, the picture as zeros. The
        # cycle is badline's column, which is where xvic's monitor puts
        # the cycle at an instruction boundary. Read: the registers, the
        # beam, the frame and field, the text window's counters and the
        # line's fetches, the light pen and the colour RAM; the character
        # line is worked out from the line and $9001, as xvic's monitor
        # works it out. The picture is painted afresh.
        module VICI
          NAME = "VIC-I"
          MAJOR = 0
          MINOR = 4
          HEADER = 0x472
          COLOR_RAM = 0x52
          REGISTERS = 0x452
          # xvic's picture: width, lines and pitch, by model.
          PICTURES = { "pal" => [1648, 312, 1648], "ntsc" => [1536, 262, 1536] }.freeze
          AREA_BEFORE = 0
          AREA_FIRST = 1
          AREA_IN = 2
          AREA_AFTER = 3
          FETCH_WAITING = 1
          FETCH_CODE = 2
          FETCH_PATTERN = 3
          FETCH_DONE = 4
          LIGHT_PEN_FLAG = 1
          FILLER = 0xff

          module_function

          def reads?(section) = section.major == MAJOR && section.minor == MINOR && section.data.bytesize >= HEADER

          # The model whose picture the module's size says, or nil.
          def model(section)
            lines = FieldReader.new(section).skip(0x46a).dword
            PICTURES.find { |_, picture| picture[1] == lines }&.first
          end

          # The module for `machine` from its BL-VICI and BL-COLORRAM fields.
          def export(machine, vic, color_ram)
            profile = machine.vic.profile
            registers = vic.bytes("registers", "\0".b * 16).bytes
            line = vic.int("raster", 0)
            column = vic.int("column", 0)
            frame_lines = vic.int("frame_lines", profile.lines_per_frame)
            fields = FieldWriter.new
            interlaced = frame_lines != profile.lines_per_frame
            fields.dword(interlaced ? 1 : 0).dword(interlaced && frame_lines != profile.interlaced_lines ? 1 : 0)
            fields.qword(machine.cycles - (line * profile.cycles_per_line) - column)
            window(fields, vic, registers, line, column)
            fields.dword(vic.int("pen.x", 0)).dword(vic.int("pen.y", 0)).dword(LIGHT_PEN_FLAG)
            fields.bytes(Array.new(8, FILLER)).byte(vic.int("code", 0))
            colors = color_ram.bytes("ram", "".b).bytes
            fields.bytes(Array.new(0x400) { |cell| colors.fetch(cell, 0) & 0x0f })
            fields.bytes(registers).dword(line)
            picture(fields, PICTURES.fetch(machine.model))
            fields.section(NAME, MAJOR, MINOR)
          end

          def window(fields, vic, registers, line, column)
            open = vic.bool("window_open", false)
            done = vic.bool("window_done", false)
            columns = registers[2] & 0x7f
            rows = (registers[3] >> 1) & 0x3f
            first = open && vic.int("text_rows", 0).zero? && vic.int("char_line", 0).zero?
            origin = registers[0] & 0x7f
            area = if open then first && column < origin ? AREA_FIRST : AREA_IN
                   else done ? AREA_AFTER : AREA_BEFORE
                   end
            state, count = fetches(vic, open && column >= origin, columns, column)
            fields.byte(column).word(line).byte(area).byte(0).byte(state).byte(0).word(line).word(0)
            fields.dword(columns).dword(rows).dword(columns)
            fields.dword(border?(open, first, done, registers, line) ? 1 : 0)
            fields.dword(vic.int("row_start", 0)).dword(0).dword(vic.int("text_rows", 0)).dword(count).word(0)
          end

          # The line's fetches as xvic counts them, from the column in
          # $9000 on: waiting, with the cycles left until the cycle before
          # the first fetch, then fetching, with the characters fetched.
          # Before that column, and off the window's lines, the count is
          # the columns.
          def fetches(vic, started, columns, column)
            return [0, columns] unless started

            from = vic.int("fetch_from", 0)
            return [FETCH_WAITING, from - 1 - column] if column < from - 1
            return [FETCH_CODE, 0] if column < from

            fetched = vic.int("fetched", 0)
            return [FETCH_DONE, columns] if fetched >= columns

            [(column - from).even? ? FETCH_PATTERN : FETCH_CODE, fetched]
          end

          # Whether xvic's flag at $27 is set: unless the window was open
          # on the line before.
          def border?(open, first, done, registers, line)
            return first if open
            return true unless done

            height = registers[3].anybits?(0x01) ? 16 : 8
            line != (registers[1] * 2) + (((registers[3] >> 1) & 0x3f) * height)
          end

          def picture(fields, (width, lines, pitch))
            fields.dword(width).dword(lines).dword(pitch).zeros((((2 * lines) + 8) * pitch) + 4)
          end

          # The colour RAM's cells, low nibbles.
          def colors(section) = FieldReader.new(section).skip(COLOR_RAM).bytes(0x400).map { |cell| cell & 0x0f }

          # BL-VICI's fields for `machine`'s profile, in a keyed module's
          # writer.
          def import(section, out, profile)
            fields = FieldReader.new(section)
            interlaced = fields.dword == 1
            short = fields.dword == 1
            fields.skip(8)
            column = fields.byte
            line = fields.word
            area = fields.byte
            fields.skip(1)
            state = fields.byte
            fields.skip(5 + 16)
            row_start = fields.dword
            fields.skip(4)
            text_rows = fields.dword
            count = fields.dword
            fields.skip(2)
            pen_x = fields.dword
            pen_y = fields.dword
            fields.skip(4 + 8)
            code = fields.byte
            registers = FieldReader.new(section).skip(REGISTERS).bytes(16)
            out.bytes("registers", registers).int("raster", line).int("column", column)
            frame_lines = if interlaced then short ? profile.interlaced_lines - 1 : profile.interlaced_lines
                          else profile.lines_per_frame
                          end
            out.int("frame_lines", frame_lines).bool("long_field", !interlaced || short)
            open = [AREA_FIRST, AREA_IN].include?(area)
            out.bool("window_open", open).bool("window_done", area == AREA_AFTER)
            fetching = open && state != FETCH_WAITING && state != 0
            out.int("row_start", row_start).int("matrix", row_start + (fetching ? count : 0))
            out.int("char_line", open ? char_line(registers, line) : 0).int("text_rows", text_rows)
            out.int("fetch_from", open ? (registers[0] & 0x7f) + Chips::VICI::FETCH_DELAY : 0)
            out.int("fetched", fetching ? count : 0).int("code", code)
            out.int("pen.x", pen_x & 0xff).int("pen.y", pen_y & 0xff)
          end

          # The line of the character row the window is on.
          def char_line(registers, line)
            height = registers[3].anybits?(0x01) ? 16 : 8
            (line - (registers[1] * 2)) % height
          end
        end
      end
    end
  end
end
