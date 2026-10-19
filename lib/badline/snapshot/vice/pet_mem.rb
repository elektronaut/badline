# frozen_string_literal: true

module Badline
  module Snapshot
    module Vice
      module PET
        # PETMEM 1.3: the board, the RAM below $8000 in K and the 8096's
        # control register at $FFF0, a byte for the SuperPET's latches, then
        # the RAM, the screen RAM, 1K or 2K as the board has, or on the 8296
        # its 32K from $8000, an 8096's, 8296's or SuperPET's 64K board, and
        # 24 bytes of xpet's own settings, which name the 2001, and on the
        # SuperPET the CPU that has the bus.
        #
        # The board is 0 for the discrete video, 1 for a 40-column CRTC, 2
        # for an 80-column one, 3 for the SuperPET, 4 for the 8096 and 5 for
        # the 8296. xpet's ROMs aren't in the snapshot.
        #
        # The SuperPET's latch byte holds the bank at $9000 in its high
        # nibble, and sets bit 0 while the bank RAM is there rather than the
        # empty socket, and bit 2 always. Its settings hold 1 at offset 2
        # while the 6809 has the bus. Both were inferred from xpet 3.10's
        # snapshots after writes to the bank latch and $EFFE, and in both
        # modes. xpet has no system latch, so the bank latch's bit 7 and the
        # system latch aren't saved, and a restore clears them. Nor is the
        # 6702: a restore leaves it as the RES line does.
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
          # The SuperPET's settings byte for the CPU, and its value while the
          # 6809 has the bus.
          SETTINGS_CPU = 2
          SETTINGS_M6809 = 0x01
          # The SuperPET's latch byte: the bit always set, and the one for
          # the bank RAM at $9000.
          LATCHES = 0x04
          BANK_RAM = 0x01
          EXPANSION = 0x10000

          module_function

          def reads?(section) = section.major == MAJOR && section.minor == MINOR

          def board(model)
            return SUPERPET if model.superpet?
            return CBM8296 if model.cbm8296?
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
            superpet = machine.superpet?
            fields = FieldWriter.new.byte(board(machine.model)).byte(0).byte(machine.ram_kb)
            fields.byte(expansion ? expansion.control : 0).byte(superpet ? latches(machine.board) : HEADER_END)
            fields.bytes(machine.ram.snapshot).bytes(bus.screen.cells)
            fields.bytes(expansion.cells) if expansion
            fields.bytes(machine.board.cells) if superpet
            settings = SETTINGS.dup
            settings[1] = SETTINGS_2001 if machine.model.basic1?
            settings[SETTINGS_CPU] = SETTINGS_M6809 if superpet && machine.m6809_running?
            fields.bytes(settings).section(NAME, MAJOR, MINOR)
          end

          def latches(board) = (board.bank << 4) | LATCHES | (board.socket.zero? ? BANK_RAM : 0)

          # Whether a SuperPET's settings say the 6809 has the bus.
          def m6809?(section)
            data = section.data
            offset = data.bytesize - SETTINGS.length + SETTINGS_CPU
            offset >= 0 && data.getbyte(offset).to_i.anybits?(SETTINGS_M6809)
          end

          # A SuperPET's bank latch, socket bit and 64K board by their
          # BL-SUPERPET keys, in a keyed module's writer.
          def import_superpet(section, out)
            fields = FieldReader.new(section).skip(4)
            latches = fields.byte
            fields.skip(fields_before_board(section))
            out.int("bank_latch", latches >> 4).int("socket", latches.anybits?(BANK_RAM) ? 0 : 1)
            out.int("system_latch", 0).bytes("ram", fields.string(EXPANSION))
          end

          # The RAM and the screen RAM before a SuperPET's board.
          def fields_before_board(section) = (ram_kb(section) * 1024) + 0x800

          # The board's number in the header.
          def board_of(section) = FieldReader.new(section).byte

          def ram_kb(section) = FieldReader.new(section).skip(2).byte

          # Whether xpet's settings at the end name a 2001.
          def pet2001?(section)
            data = section.data
            data.bytesize >= SETTINGS.length && data.getbyte(data.bytesize - SETTINGS.length + 1).to_i.anybits?(0x01)
          end

          # The RAM, the screen RAM and an 8096's or 8296's board and control
          # register
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
            return unless [CBM8096, CBM8296].include?(board)

            out.int("expansion.control", control).bytes("expansion.ram", fields.string(EXPANSION))
          end
        end
      end
    end
  end
end
