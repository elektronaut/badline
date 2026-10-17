# frozen_string_literal: true

module Badline
  module Snapshot
    module Vice
      module PET
        # PETMEM 1.3: the board, the RAM below $8000 in K and the 8096's
        # control register at $FFF0, then the RAM, the screen RAM, 1K or 2K
        # as the board has, an 8096's 64K board, and 24 bytes of xpet's own
        # settings, which name the 2001.
        #
        # The board is 0 for the discrete video, 1 for a 40-column CRTC, 2
        # for an 80-column one, 3 for the SuperPET, 4 for the 8096 and 5 for
        # the 8296. xpet's ROMs aren't in the snapshot.
        module PETMem
          NAME = "PETMEM"
          MAJOR = 1
          MINOR = 3
          DISCRETE = 0
          CRTC40 = 1
          CRTC80 = 2
          SUPERPET = 3
          CBM8096 = 4
          CBM8296 = 5
          # The byte after the header's control register, as xpet writes it.
          HEADER_END = 0x05
          # xpet's settings at the end, but for the second byte, which is
          # SETTINGS_2001 on a 2001.
          SETTINGS = [0x00, 0x00, 0x00, 0x00, 0xd6, 0x01, 0x00, 0x20, 0x00, 0x04, 0x00, 0x40, 0x00, 0x00, 0x00,
                      0x01, 0x00, 0x00, 0x00, 0x10, 0x00, 0x02, 0x00, 0x00].freeze
          SETTINGS_2001 = 0x03
          EXPANSION = 0x10000

          module_function

          def reads?(section) = section.major == MAJOR && section.minor == MINOR

          def board(model)
            return CBM8096 if model.expansion

            case model.video
            when :crtc40 then CRTC40
            when :crtc80 then CRTC80
            else DISCRETE
            end
          end

          def export(machine)
            bus = machine.bus
            expansion = bus.expansion
            fields = FieldWriter.new.byte(board(machine.model)).byte(0).byte(machine.ram_kb)
            fields.byte(expansion ? expansion.control : 0).byte(HEADER_END)
            fields.bytes(machine.ram.snapshot).bytes(bus.screen.cells)
            fields.bytes(expansion.cells) if expansion
            settings = SETTINGS.dup
            settings[1] = SETTINGS_2001 if machine.model.basic1?
            fields.bytes(settings).section(NAME, MAJOR, MINOR)
          end

          # The board's number in the header.
          def board_of(section) = FieldReader.new(section).byte

          def ram_kb(section) = FieldReader.new(section).skip(2).byte

          # Whether xpet's settings at the end name a 2001.
          def pet2001?(section)
            data = section.data
            data.bytesize >= SETTINGS.length && data.getbyte(data.bytesize - SETTINGS.length + 1).to_i.anybits?(0x01)
          end

          # The RAM, the screen RAM and an 8096's board and control register
          # by their BL-RAM keys, in a keyed module's writer, for a machine
          # with `screen_bytes` of screen RAM.
          def import(section, out, screen_bytes)
            fields = FieldReader.new(section)
            board = fields.byte
            fields.skip(1)
            ram_kb = fields.byte
            control = fields.byte
            fields.skip(1)
            out.bytes("ram", fields.string(ram_kb * 1024)).bytes("screen", fields.string(screen_bytes))
            return unless board == CBM8096

            out.int("expansion.control", control).bytes("expansion.ram", fields.string(EXPANSION))
          end
        end
      end
    end
  end
end
