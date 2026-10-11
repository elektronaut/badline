# frozen_string_literal: true

module Badline
  class C128
    class VDC
      # The VDC's state for a snapshot.
      module SavedState
        # Everything the VDC holds but its display, which it paints again
        # while it renders: the registers, the RAM, the data port and the
        # raster. Whether it renders is the host's.
        def save_state(out)
          out.marker("VDC")
          out.ints(@registers).blob(@memory.ram)
          out.int(@selected).int(@read_latch).int(@write_data).int(@busy_until).int(@phase).int(@line_units)
          @raster.save_state(out)
          @painter.save_state(out)
        end

        def load_state(input)
          input.marker("VDC")
          input.ints_into(@registers)
          input.blob_into(@memory.ram)
          @memory.mode64 = @registers[28].anybits?(0x10)
          @selected = input.int
          @read_latch = input.int
          @write_data = input.int
          @busy_until = input.int
          @phase = input.int
          @line_units = input.int
          @raster.load_state(input)
          @painter.load_state(input)
        end
      end
    end
  end
end
