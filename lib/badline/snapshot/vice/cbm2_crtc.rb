# frozen_string_literal: true

module Badline
  module Snapshot
    module Vice
      module CBM2
        # CRTC 1.2 as xcbm2 saves it, laid out as xpet's (PET::CRTC): the
        # board's screen settings, the registers, the one selected, the
        # beam, the picture's size and the frame's lines, then xcbm2's
        # picture. xcbm2's board has the 6845's cursor and reads one byte a
        # character from 2K of screen RAM. After the beam's line come the
        # fields left in the cursor's blink phase, counted down from 32, and
        # whether the cursor shows: xcbm2 blinks it 32 fields on and 32 off,
        # where badline's 6845 blinks it 16 and 16, or 8 and 8.
        #
        # xcbm2 ticks the mains once a frame, as vertical sync ends, so its
        # mains follows the CRTC (Mains).
        #
        # Written: the registers and the beam as badline's CRTC has them,
        # and the cursor shown as badline's is, its phase scaled to xcbm2's.
        # The picture is left blank, as xcbm2 paints it again. Read: the
        # registers and the beam as xpet's are (PET::CRTC), the cursor shown
        # as xcbm2's is, its phase scaled to badline's, and where the
        # picture is in its frame. The picture starts again with the next
        # frame.
        module CRTC
          NAME = PET::CRTC::NAME
          SETTINGS = [0xff, 0x07, 0x00, 0x10, 0x00, 0x20, 0x00, 0xe0, 0xff, 0x3f].freeze
          # The 6845's cursor, one byte a character, and not a 2001.
          BOARD = [0x01, 0x01, 0x00].freeze
          WIDTH = 704
          # The picture's lines and the line its first row starts on, for a
          # 600 and a 700.
          FRAMES = { false => [266, 33], true => [366, 8] }.freeze
          BLINK = 32
          # Where R10 is in the module, and the blink's fields left.
          R10_AT = PET::CRTC::SETTINGS.length + 5 + 10
          BLINK_AT = PET::CRTC::SELECTED + 4
          # R10's blink of 8 fields on and 8 off.
          FAST_BLINK = 0x40

          module_function

          def reads?(section) = PET::CRTC.reads?(section)

          def fresh_crtc(machine) = CBM2Setup.of(machine).build.crtc

          # The module from the BL-CRTC and BL-VIDEO fields in `crtc_input`
          # and `video_input`.
          def export(machine, crtc_input, video_input)
            registers = PET::CRTC.crtc_registers(crtc_input)
            beam = beam(machine, crtc_input, registers)
            height, top = FRAMES.fetch(machine.model.high_profile)
            fields = FieldWriter.new.bytes(SETTINGS).word(0).bytes(BOARD).bytes(registers)
            fields.byte(crtc_input.int("selected", 0)).byte(beam.column).byte(beam.row).byte(beam.raster)
            fields.bytes(blink(video_input.int("frames", 0), registers[10])).byte(1)
            fields.word(0).word(beam.start & PET::CRTC::SCREEN_BITS).byte(beam.vsync).byte(0).flag(beam.shown)
            fields.word(WIDTH).word(height).byte(PET::CRTC::AFTER_SIZE).zeros(3).byte(top).byte(0)
            fields.word(PET::CRTC.frame_lines(registers)).word(beam.frame_line).byte(1)
            fields.dword(0).dword(WIDTH).dword(height).dword(WIDTH).zeros(WIDTH * (height + 4))
            fields.section(NAME, PET::CRTC::MAJOR, PET::CRTC::MINOR)
          end

          # The beam where xcbm2's is with badline's CRTC where `input` has
          # it (PET::CRTC::CRTC_LEAD). On a line's last character xcbm2's
          # beam has moved on to the next line, a cycle before it starts.
          def beam(machine, input, registers)
            cycles = -PET::CRTC::CRTC_LEAD % PET::CRTC.frame_cycles(registers)
            beam = PET::CRTC.crtc_beam(PET::CRTC.run_on(fresh_crtc(machine), input, cycles), registers)
            return beam unless beam.column == registers[0]

            PET::CRTC.crtc_beam(PET::CRTC.run_on(fresh_crtc(machine), input, cycles + 1), registers).with(column: 0xff)
          end

          # The fields left in xcbm2's blink phase and whether its cursor
          # shows, for badline's fields counted, `frames`, and R10.
          def blink(frames, r10)
            fast = r10 & 0x60 == FAST_BLINK
            shown = frames.nobits?(fast ? 0x08 : 0x10)
            phase = fast ? (frames & 0x07) << 1 : frames & 0x0f
            [BLINK - (phase << 1), shown ? 1 : 0]
          end

          # badline's fields counted for xcbm2's blink in `section`.
          def frames(section)
            r10 = FieldReader.new(section).skip(R10_AT).byte
            left, shown = FieldReader.new(section).skip(BLINK_AT).bytes(2)
            phase = ((BLINK - [left, BLINK].min) >> 1) & 0x0f
            return (shown.zero? ? 0x08 : 0) | (phase >> 1) if r10 & 0x60 == FAST_BLINK

            (shown.zero? ? 0x10 : 0) | phase
          end

          # The BL-CRTC module, run on from xcbm2's beam as xpet's is.
          def import(section, machine)
            counters = Keyed.section("BL-CRTC") { |out| PET::CRTC.import(section, out, 1, 0) }
            frame = PET::CRTC.frame_cycles(PET::CRTC.registers(section))
            cycles = (PET::CRTC::CRTC_LEAD + PET::CRTC.column_of(section)) % frame
            fields = PET::CRTC.run_on(fresh_crtc(machine), Keyed::Reader.parse(counters), cycles)
            Keyed.section("BL-CRTC") { |out| PET::CRTC.copy(fields, out) }
          end

          # The BL-VIDEO module for a CRTC whose BL-CRTC fields `crtc` holds:
          # the cursor's blink, the line the frame paints next and the frame's
          # layout. The picture stays as the machine has it.
          def video(section, crtc)
            registers = PET::CRTC.crtc_registers(crtc)
            Keyed.section("BL-VIDEO") do |out|
              out.int("frames", frames(section)).int("line", painted(crtc, registers)).bool("line_shown", false)
              out.int("origin", Badline::CBM2::CRTCVideo::LEFT - ((registers[0] + 1 - registers[2]) << 3))
              out.ints("layout", registers.values_at(0, 1, 2, 4, 5, 6, 9, 12, 13))
            end
          end

          # The lines the frame has displayed so far.
          def painted(crtc, registers)
            lines = registers[9] + 1
            shown = registers[6] * lines
            return shown if crtc.bool("adjusting", false) || !crtc.bool("row_display", true)

            [(crtc.int("row", 0) * lines) + crtc.int("line", 0), shown].min
          end
        end
      end
    end
  end
end
