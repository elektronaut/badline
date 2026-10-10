# frozen_string_literal: true

module Badline
  class Vic20
    class Bus
      # The bus's state for a snapshot.
      module SavedState
        # The RAM, the colour RAM, the byte each side's data lines hold and the
        # cartridge's ROM chips, for a snapshot. The expansion blocks are how
        # the machine was built.
        def save_state(out)
          out.marker("VIC20 BUS")
          @ram.save_state(out)
          out.blob(@color_ram.cells).int(@data).int(@video_data).int(@roms.length)
          @roms.each do |rom|
            out.int(rom.start)
            rom.save_state(out)
          end
        end

        def load_state(input)
          input.marker("VIC20 BUS")
          @ram.load_state(input)
          input.blob_into(@color_ram.cells)
          @data = input.int
          @video_data = input.int
          chips = Array.new(input.int) { [input.int, input.blob] }
          @roms = []
          chips.each { |chip| @roms << ROM.new(chip[1], length: chip[1].length, start: chip[0]) }
          map_pages
        end
      end
    end
  end
end
