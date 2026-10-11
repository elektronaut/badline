# frozen_string_literal: true

module Badline
  class Vic20
    class Bus
      class ColorRAM
        # The cells in a keyed snapshot module, under `key`.
        def save_fields(out, key) = out.bytes(key, @cells)

        def load_fields(input, key) = input.bytes_into(key, @cells)
      end

      # The bytes each side's data lines hold, under `prefix`, and a
      # cartridge's ROM chips as rom<N>.start and rom<N>.bytes, in a keyed
      # snapshot module (Snapshot::Keyed). The pages are mapped again once
      # they are loaded.
      module KeyedState
        def save_fields(out, prefix)
          out.int("#{prefix}data", @data).int("#{prefix}video_data", @video_data)
        end

        def load_fields(input, prefix)
          @data = input.byte("#{prefix}data", @data)
          @video_data = input.byte("#{prefix}video_data", @video_data)
        end

        # Whether a cartridge's ROM chips are in the expansion blocks.
        def cartridge? = !@roms.empty?

        def save_rom_fields(out)
          out.int("roms", @roms.length)
          @roms.each_with_index do |rom, number|
            out.int("rom#{number}.start", rom.start)
            rom.save_fields(out, "rom#{number}.bytes")
          end
        end

        def load_rom_fields(input)
          @roms = []
          input.int("roms", 0).times do |number|
            bytes = input.bytes("rom#{number}.bytes", "".b).bytes
            @roms << ROM.new(bytes, length: bytes.length, start: input.word("rom#{number}.start", 0))
          end
        end

        def restored! = map_pages
      end

      include KeyedState
    end
  end
end
