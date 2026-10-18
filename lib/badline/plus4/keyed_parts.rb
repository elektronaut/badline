# frozen_string_literal: true

module Badline
  class Plus4
    class CPUPort
      # The port's registers in a keyed snapshot module (Snapshot::Keyed),
      # under `prefix`. The serial bus's lines and the datasette's write
      # line are driven again from them once everything is loaded
      # (#restored!), without recording an edge on the tape.
      module KeyedState
        def save_fields(out, prefix)
          out.int("#{prefix}ddr", @ddr).int("#{prefix}data", @data)
        end

        def load_fields(input, prefix)
          @ddr = input.byte("#{prefix}ddr", @ddr)
          @data = input.byte("#{prefix}data", @data)
        end

        def restored!
          @serial_bus.host_lines = serial_lines
          @datasette.write_level = levels.anybits?(CLK_OUT)
        end
      end

      include KeyedState
    end

    class KeyboardPort
      # The 6529's latch in a keyed snapshot module (BL-KEYPORT).
      module KeyedState
        def save_fields(out) = out.int("output", @output)

        def load_fields(input)
          @output = input.byte("output", @output)
        end
      end

      include KeyedState
    end

    class UserPort
      # The 6529's latch in a keyed snapshot module (BL-USERPORT).
      module KeyedState
        def save_fields(out) = out.int("output", @output)

        def load_fields(input)
          @output = input.byte("output", @output)
        end
      end

      include KeyedState
    end

    class Bus
      # The ROM bank latch, whether ROM is selected and the last byte on the
      # bus, under `prefix`, and the cartridges' ROMs by slot (#save_slot_fields),
      # in keyed snapshot modules (Snapshot::Keyed). The TED learns which
      # memory is selected, and the pages are mapped again, once they are
      # loaded (#restored!). The BASIC, KERNAL and function ROMs come with
      # the model.
      module KeyedState
        # The cartridge slots, as xplus4 names them: cartridge 1 or 2, the
        # low ($8000) or the high ($C000) half.
        SLOTS = %w[c1lo c2lo c1hi c2hi].freeze

        def save_fields(out, prefix)
          out.int("#{prefix}low_bank", @low_bank).int("#{prefix}high_bank", @high_bank)
          out.bool("#{prefix}rom_selected", @rom_selected).int("#{prefix}data", @data)
        end

        def load_fields(input, prefix)
          @low_bank = input.masked("#{prefix}low_bank", @low_bank, 0x03)
          @high_bank = input.masked("#{prefix}high_bank", @high_bank, 0x03)
          @rom_selected = input.bool("#{prefix}rom_selected", @rom_selected)
          @data = input.byte("#{prefix}data", @data)
        end

        # Whether a cartridge's ROM is in any slot.
        def cartridge?
          index = 0
          while index < SLOTS.length
            return true unless slot_rom(index).nil?

            index += 1
          end
          false
        end

        # Each slot's ROM, 16K, under its name. An empty slot writes
        # nothing.
        def save_slot_fields(out)
          SLOTS.each_with_index do |name, index|
            rom = slot_rom(index)
            rom&.save_fields(out, name)
          end
          out
        end

        # A slot the module holds nothing for is left empty.
        def load_slot_fields(input)
          SLOTS.each_with_index do |name, index|
            bytes = input.bytes(name, "".b).bytes
            if index < 2
              @low_roms[2 + index] = slot(bytes, 0x8000)
            else
              @high_roms[index] = slot(bytes, 0xc000)
            end
          end
        end

        def restored!
          @ted.rom_selected = @rom_selected
          map_ram
        end

        private

        def slot_rom(index) = index < 2 ? @low_roms[2 + index] : @high_roms[index]

        # A slot's ROM from its bytes at `start`, or none.
        def slot(bytes, start) = bytes.empty? ? nil : ROM.new(bytes, length: bytes.length, start:)
      end

      include KeyedState
    end
  end
end
