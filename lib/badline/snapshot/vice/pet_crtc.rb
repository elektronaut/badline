# frozen_string_literal: true

module Badline
  module Snapshot
    module Vice
      module PET
        # CRTC 1.2, which xpet saves on every model, the discrete boards'
        # video too, as a 6545 with the registers fixed: the board's screen
        # settings, the registers, the one selected, the beam's character,
        # row and line in the row, whether the frame is in its vertical
        # adjust, the row's start in screen RAM, the lines of vertical sync
        # left, whether the rows show, the picture's size, the lines in the
        # frame and the line in it, then xpet's picture.
        #
        # Written: the registers and the beam as badline's CRTC, or its
        # discrete video, has them. The picture is left blank, as xpet
        # paints it again.
        #
        # Read: the registers and the beam, with what follows from them: the
        # memory address, the characters since horizontal sync and whether
        # the character shows. The picture starts again with the next
        # frame.
        module CRTC
          NAME = "CRTC"
          MAJOR = 1
          MINOR = 2
          # The registers xpet saves, two more than badline's CRTC has.
          REGISTERS = 20
          # Where the selected register is in the module, and the beam after
          # it.
          SELECTED = 0x23
          # The board's screen settings xpet saves ahead of the registers:
          # the screen RAM's masks and the bits of the frame's start address
          # it latches (BOARD_ATTRIBUTES), then the bytes a character reads
          # and whether the board is a 2001's.
          SETTINGS = [0xff, 0x03, 0x00, 0x20, 0x00, 0x20, 0x00, 0x10, 0xff, 0x1f].freeze
          # The 8296's, whose screen RAM spans 4K.
          SETTINGS_8296 = [0xff, 0x0f, 0x00, 0x20, 0x00, 0x20, 0xff, 0x0f, 0xff, 0x1f].freeze
          # The 2001's and 3000 series' video as xpet's CRTC runs it: 64
          # cycles a line, 32 rows of 8 lines and 4 more, the first 25 rows
          # shown.
          DISCRETE_REGISTERS = [0x3f, 0x28, 0x32, 0x08, 0x1f, 0x04, 0x19, 0x1d, 0x00, 0x07, 0x00, 0x00, 0x10, 0x00,
                                0x00, 0x00, 0x00, 0x00, 0x00, 0x00].freeze
          DISCRETE_HEIGHT = 216
          DISCRETE_LINE = 64
          DISCRETE_FRAME = DISCRETE_LINE * 260
          # How many cycles badline's beam runs ahead of xpet's, where both
          # drop the vertical drive line on the same cycle.
          DISCRETE_LEAD = 20
          CRTC_LEAD = -3
          HEIGHT = 272
          # A byte xpet writes after the picture's size.
          AFTER_SIZE = 0x20
          # The memory address's bits that pick a byte of screen RAM.
          SCREEN_BITS = 0x0fff
          # The bits above them, which the boards decode as attributes.
          HIGH_BITS = 0x3000

          # Where the beam is, in xpet's terms: the character, the row and
          # its line, the lines of vertical sync left, whether the rows show,
          # the row's start address and the line in the frame.
          Beam = Data.define(:column, :row, :raster, :vsync, :shown, :start, :frame_line)

          module_function

          def reads?(section) = section.major == MAJOR && section.minor == MINOR

          def width(model) = model.video == :crtc80 ? 704 : 384

          def height(model) = model.video == :discrete ? DISCRETE_HEIGHT : HEIGHT

          def columns(model) = model.video == :crtc80 ? 2 : 1

          # The frame's start address bits xpet latches on the board: MA12,
          # which inverts the 80-column boards' picture.
          def attributes(model) = model.video == :crtc80 ? 0x1000 : 0

          def export(machine, crtc_input, video_input)
            model = machine.model
            discrete = model.video == :discrete
            registers = discrete ? DISCRETE_REGISTERS : crtc_registers(crtc_input)
            beam = if discrete
                     discrete_beam(video_input)
                   else
                     crtc_beam(run_on(machine, crtc_input, -CRTC_LEAD % frame_cycles(registers)), registers)
                   end
            fields = FieldWriter.new.bytes(model.cbm8296? ? SETTINGS_8296 : SETTINGS).word(attributes(model))
            fields.byte(0).byte(columns(model))
            fields.byte(model.basic1? ? 1 : 0).bytes(registers).byte(discrete ? 0 : crtc_input.int("selected", 0))
            beam_fields(fields, beam, registers, model)
            picture(fields, model)
            fields.section(NAME, MAJOR, MINOR)
          end

          def crtc_registers(input)
            registers = input.bytes("registers", "".b).bytes
            Array.new(REGISTERS) { |index| registers[index] || 0 }
          end

          def beam_fields(fields, beam, registers, model)
            fields.byte(beam.column).byte(beam.row).byte(beam.raster).zeros(2).flag(beam.raster.zero?)
            fields.word(beam.start & attributes(model)).word((beam.start & SCREEN_BITS) * columns(model))
            fields.byte(beam.vsync).byte(0).flag(beam.shown)
            fields.word(width(model)).word(height(model)).byte(AFTER_SIZE).zeros(3)
            shown = registers[6] * (registers[9] + 1)
            fields.byte([(height(model) - shown) / 2, 0].max).byte(0)
            fields.word(frame_lines(registers)).word(beam.frame_line).byte(0)
          end

          # Blank, as xpet paints it again: the line it draws, its size twice
          # over, and four lines more than it shows.
          def picture(fields, model)
            width = width(model)
            height = height(model)
            fields.dword(0).dword(width).dword(height).dword(width).zeros(width * (height + 4))
          end

          def frame_lines(registers) = ((registers[4] + 1) * (registers[9] + 1)) + registers[5]

          def frame_cycles(registers) = (registers[0] + 1) * frame_lines(registers)

          # The BL-CRTC fields of a CRTC loaded with those in `input` and run
          # `cycles` cycles on its own, in a machine built as `machine` was.
          def run_on(machine, input, cycles)
            crtc = PETSetup.of(machine).build.crtc
            crtc.load_fields(input)
            cycles.times { crtc.cycle! }
            Keyed::Reader.parse(Keyed.section("BL-CRTC") { |out| crtc.save_fields(out) })
          end

          # Writes the BL-CRTC fields `input` holds to `out`.
          def copy(input, out)
            out.bytes("registers", input.bytes("registers", "".b)).int("selected", input.int("selected", 0))
            %w[column since_hsync line row vsync_lines row_start address].each { |key| out.int(key, input.int(key, 0)) }
            %w[adjusting row_display column_display].each { |key| out.bool(key, input.bool(key, false)) }
          end

          # Both move a row's start on at R1 of its last line.
          def crtc_beam(input, registers)
            column = input.int("column", 0)
            row = input.int("row", 0)
            line = input.int("line", 0)
            adjusting = input.bool("adjusting", false)
            start = input.int("row_start", 0)
            rows = registers[4] + 1
            lines = registers[9] + 1
            Beam.new(column:, row: adjusting ? rows : row, raster: adjusting ? 0 : line,
                     vsync: input.int("vsync_lines", 0), shown: input.bool("row_display", true), start:,
                     frame_line: adjusting ? (rows * lines) + line : (row * lines) + line)
          end

          # Whether the row's start has moved on by `column` of `line`.
          def moved?(line, column, registers)
            line > registers[9] || (line == registers[9] && column > registers[1])
          end

          # The discrete video's line in the frame, in xpet's fixed rows: the
          # rows show until line 200, vertical sync runs from row 29 for 16
          # lines, and the 4 lines past row 31 are the vertical adjust.
          def discrete_beam(input)
            cycle = ((input.int("line", 0) * DISCRETE_LINE) + input.int("column", 0) - DISCRETE_LEAD) % DISCRETE_FRAME
            line = cycle / DISCRETE_LINE
            row = [line >> 3, 32].min
            adjusting = row == 32
            raster = adjusting ? 0 : line & 0x07
            column = cycle % DISCRETE_LINE
            sync = line - (DISCRETE_REGISTERS[7] * 8)
            moved = !adjusting && moved?(raster, column, DISCRETE_REGISTERS)
            Beam.new(column:, row:, raster:, vsync: sync.between?(0, 15) ? 16 - sync : 0, shown: line < 200,
                     start: 0x1000 + ((moved ? row + 1 : row) * 40), frame_line: line)
          end

          # The beam the module holds, with the row's start as the module
          # has it: the attribute bits latched in the high word and the
          # offset into screen RAM, in bytes, in the low.
          def beam(section)
            fields = FieldReader.new(section).skip(SELECTED + 1)
            column, row, raster = fields.bytes(3)
            fields.skip(3)
            latched = fields.word
            offset = fields.word
            vsync = fields.byte
            fields.skip(1)
            shown = fields.flag?
            fields.skip(12)
            Beam.new(column:, row:, raster:, vsync:, shown:, start: (latched << 16) | offset,
                     frame_line: fields.word)
          end

          def registers(section) = FieldReader.new(section).skip(SETTINGS.length + 5).bytes(REGISTERS)

          def selected(section) = FieldReader.new(section).skip(SELECTED).byte

          # How many cycles into its line xpet's beam is. A beam whose line
          # has moved on a cycle before it starts holds -1.
          def column_of(section)
            column = beam(section).column
            column < 0x80 ? column : column - 0x100
          end

          # The CRTC's fields by their BL-CRTC keys at the start of the line
          # the module's beam is in (#column_of), in a keyed module's writer,
          # for a board that reads `columns` bytes a character with
          # `attributes` latched from the frame's start.
          def import(section, out, columns, attributes)
            registers = registers(section)
            beam = beam(section)
            rows = registers[4] + 1
            adjusting = beam.row >= rows
            line = adjusting ? beam.frame_line - (rows * (registers[9] + 1)) : beam.raster
            start = start_address(beam.start, registers, columns, attributes)
            start = (start - registers[1]) & 0x3fff if !adjusting && moved?(line, column_of(section), registers)
            out.bytes("registers", registers.first(Chips::CRTC::MASKS.length)).int("selected", selected(section) & 0x1f)
            out.int("column", 0).int("line", [line, 0].max).int("row", adjusting ? rows - 1 : beam.row)
            out.int("since_hsync", registers[0] + 1 - registers[2]).int("vsync_lines", beam.vsync)
            out.bool("adjusting", adjusting).bool("row_display", beam.shown).bool("column_display", true)
            out.int("row_start", start).int("address", start)
          end

          # The row's start address from the module's (#beam): the bits
          # that pick screen RAM from its offset, the attribute bits the
          # board latches from its high word, and those above from R12.
          def start_address(start, registers, columns, attributes)
            high = (registers[12] << 8) & HIGH_BITS & ~attributes
            high | ((start >> 16) & attributes) | (((start & 0xffff) / columns) & SCREEN_BITS)
          end

          # The discrete video's fields by their BL-VIDEO keys, in a keyed
          # module's writer.
          def import_discrete(section, out)
            cycle = ((beam(section).frame_line * DISCRETE_LINE) + column_of(section) + DISCRETE_LEAD) % DISCRETE_FRAME
            out.int("column", cycle % DISCRETE_LINE).int("line", cycle / DISCRETE_LINE)
          end
        end
      end
    end
  end
end
