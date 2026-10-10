# frozen_string_literal: true

module Badline
  class Computer
    # What the C128 does as the C64 does: the NMI line, a PRG put into RAM
    # and the region's timing. Computer and C128 each include it.
    module Common
      # The clock, the raster and the crop of the machine's region, a pixel
      # to a window pixel.
      def timing
        region = address_bus.region
        Timing.new(clock_hz: region.clock_hz, cycles_per_line: region.cycles_per_line,
                   lines_per_frame: region.lines_per_frame, crop: region.crop, pixel_width: 1)
      end

      def load_prg(data)
        uint16(data[0], data[1]).tap do |load_addr|
          ram.write(load_addr, data[2..])
        end
      end

      private

      # The NMI line is wired-OR between CIA 2, the cartridge and the RESTORE
      # key, and the CPU takes an interrupt on its falling edge.
      def drive_nmi
        nmi = @cia2.interrupted? || @cartridge_nmi || @restore_pulse
        @restore_pulse = false
        @cpu.nmi = true if nmi && !@nmi_asserted
        @nmi_asserted = nmi
      end
    end
  end
end
