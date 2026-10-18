# frozen_string_literal: true

module Badline
  module Snapshot
    module Vice
      module P500
        # VIC-II 1.3 as xcbm5x0 writes it, which runs VICE's line-based
        # VIC-II rather than x64sc's, so the module is laid out otherwise
        # than x64sc's under the same name: whether bad lines may happen,
        # whether this line is one, the vertical border, the colour
        # buffer, colour RAM, whether the sequencer is idle, the light
        # pen's trigger and position, the video matrix buffer, the sprites
        # whose DMA starts next line, a word xcbm5x0 keeps at $00100000,
        # the beam's cycle and line, the registers, the sprite collisions
        # pending, the sprites' DMA, the VIC's bank, VC, the matrix's
        # width, VCBASE, then sprite and drawing fields with the bank
        # again, the line its picture draws next and its size, and the
        # picture. xcbm5x0's cycle in the line is badline's column.
        #
        # Written: the registers, colour RAM, the buffers, the beam with
        # its counters and the sprites' DMA as badline's VIC has them, the
        # bank as TPI2's PC6 and PC7 pick it, and the rest as xcbm5x0
        # leaves it. The picture is left blank, as xcbm5x0 paints it again.
        #
        # Read: the registers, colour RAM, the buffers, the beam with VC,
        # VCBASE and whether the sequencer is idle, the light pen and the
        # sprites' DMA, through the x64sc module's reader (VICII::Import).
        # The row counter follows from the line and YSCROLL, and the
        # sprites' counters and the borders' flip-flops start afresh.
        # xcbm5x0's VIC isn't x64sc's, so a program badline runs on from its
        # snapshot reads the raster a cycle or so off now and then.
        module VICII
          NAME = Vice::VICII::NAME
          MAJOR = 1
          MINOR = 3
          ALLOW_BAD_LINES = 0x000
          BAD_LINE = 0x001
          BLANK = 0x002
          COLOR_BUFFER = 0x003
          COLOR_RAM = 0x02b
          IDLE = 0x42b
          LIGHT_PEN = 0x42c
          MATRIX_BUFFER = 0x42f
          RAM_BASE = 0x458
          CYCLE = 0x45c
          LINE = 0x45d
          REGISTERS = 0x45f
          SPRITE_DMA = 0x4a0
          BANK = 0x4a2
          VC = 0x4a4
          VC_ADD = 0x4a6
          VC_BASE = 0x4a7
          VIDEO_INT = 0x4a9
          DRAW_FLAGS = 0x4cd
          FETCH_BANK = 0x4cf
          DRAWN_LINE = 0x4d1
          PICTURE = 0x4d5
          HEADER = 0x4e1
          # The picture's size: PAL's and NTSC's.
          SIZES = { 312 => [504, 312], 263 => [520, 275] }.freeze

          module_function

          def reads?(section) = section.major == MAJOR && section.minor == MINOR

          # The lines xcbm5x0's picture has, which name its region.
          def picture_lines(section) = FieldReader.new(section).skip(PICTURE + 4).dword

          def export(machine)
            vic = machine.vic
            width, height = SIZES.fetch(vic.region.lines_per_frame)
            bytes = Array.new(HEADER + (width * (height + 4)), 0)
            sequencer(vic, bytes)
            bytes[COLOR_RAM, 0x400] = Array.new(0x400) { |offset| machine.color_ram.nibble(0xd400 + offset) }
            beam(vic, bytes)
            bank = ((machine.tpi2.port_c_output >> 6) & 0x03) << 14
            [BANK, FETCH_BANK].each { |at| word(bytes, at, bank) }
            [RAM_BASE + 2, DRAW_FLAGS].each { |at| bytes[at] = 0x10 }
            bytes[VIDEO_INT] = 1
            [vic.rasterline, width, height, width].each_with_index do |value, n|
              dword(bytes, DRAWN_LINE + (4 * n), value)
            end
            FieldWriter.new.bytes(bytes).section(NAME, MAJOR, MINOR)
          end

          # The sequencer's state and the buffers it reads.
          def sequencer(vic, bytes)
            state = vic.display_state
            bytes[ALLOW_BAD_LINES] = state.bad_lines_enabled ? 1 : 0
            bytes[BAD_LINE] = state.bad_line_condition? ? 1 : 0
            bytes[BLANK] = vic.sequencer.borders.first ? 1 : 0
            bytes[COLOR_BUFFER, 40] = vic.color_buffer.map { |value| value || 0 }
            bytes[IDLE] = state.display? ? 0 : 1
            bytes[MATRIX_BUFFER, 40] = vic.character_buffer.map { |value| value || 0 }
          end

          # The beam, the registers and the counters.
          def beam(vic, bytes)
            state = vic.display_state
            bytes[CYCLE] = vic.column
            word(bytes, LINE, vic.rasterline)
            bytes[REGISTERS, 0x40] = vic.register_file
            bytes[SPRITE_DMA] = 8.times.sum { |n| vic.sprites[n].displaying? ? 1 << n : 0 }
            word(bytes, VC, state.vc)
            bytes[VC_ADD] = 40
            word(bytes, VC_BASE, state.vc_base)
          end

          def word(bytes, at, value) = bytes[at, 2] = [value & 0xffff].pack("v").bytes

          def dword(bytes, at, value) = bytes[at, 4] = [value].pack("V").bytes

          def import(section, vic, color_ram)
            Import.new(section, vic.region).apply_to(vic, color_ram, 0xd400)
          end

          # Reads xcbm5x0's module into the fields x64sc's reader puts into
          # badline's VIC.
          class Import < Vice::VICII::Import
            # x64sc's cycle is badline's column plus one, its cycle 0 the
            # last column of the line before (VICII.vice_cycle).
            def initialize(section, region)
              super(nil)
              bytes = section.data.bytes
              @registers = bytes[REGISTERS, 0x40]
              line = bytes[LINE] | (bytes[LINE + 1] << 8)
              @cycle = (bytes[CYCLE] + 1) % region.cycles_per_line
              @line = @cycle.zero? ? (line + 1) % region.lines_per_frame : line
              @frame_start = false
              @irq_status = @registers[0x19]
              @raster_match = false
              @character_buffer = bytes[MATRIX_BUFFER, 40]
              @color_buffer = bytes[COLOR_BUFFER, 40]
              read_old_counters(bytes)
              @color_ram = bytes[COLOR_RAM, 0x400]
              @sprite_mc = Array.new(8, 0)
              @sprite_mcbase = Array.new(8, 0)
              @sprite_exp_ff = 0
            end

            private

            def read_old_counters(bytes)
              @bad_lines_enabled = !bytes[ALLOW_BAD_LINES].zero?
              @collisions = [@registers[0x1e], @registers[0x1f]]
              @display = bytes[IDLE].zero?
              @vc_base = bytes[VC_BASE] | (bytes[VC_BASE + 1] << 8)
              @vc = bytes[VC] | (bytes[VC + 1] << 8)
              @rc = @display ? (@line - @registers[0x11]) & 0x07 : 7
              @vmli = 0
              @lp_low = false
              @lp_triggered = !bytes[LIGHT_PEN].zero?
              @fetch_d011 = @registers[0x11]
              @dma_bits = bytes[SPRITE_DMA]
              @display_bits = @dma_bits
              blank = !bytes[BLANK].zero?
              @vertical_border = blank
              @vertical_armed = false
              @main_border = blank
            end
          end
        end
      end
    end
  end
end
