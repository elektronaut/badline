# frozen_string_literal: true

module Badline
  class CBM2
    class P500
      # Page $D8 of segment 15: the VIC-II's 64 registers, repeated over the
      # page.
      class VICPage
        def initialize(vic)
          @vic = vic
        end

        def peek(addr) = @vic.peek(0xd000 | (addr & 0x3f))

        def poke(addr, value)
          @vic.poke(0xd000 | (addr & 0x3f), value)
        end
      end

      # The colour RAM's four bits at $D400-$D7FF of segment 15, which the
      # CPU reads with 0 in the high four, as xcbm5x0 does.
      class ColorPages
        def initialize(color_ram)
          @color_ram = color_ram
        end

        def peek(addr) = @color_ram.nibble(addr)

        def poke(addr, value)
          @color_ram.poke(addr, value)
        end
      end

      # A TPI's page, $DE or $DF of segment 15. TPI1's CA and CB are STATVID
      # and VICDOTSEL, and TPI2's PC6 and PC7 the VIC's bank lines, which
      # an access to either chip can move, so the machine takes them again
      # after each one (P500#update_video_bus).
      class TPIPage
        def initialize(tpi, machine)
          @tpi = tpi
          @machine = machine
        end

        def peek(addr)
          value = @tpi.peek(addr)
          @machine.update_video_bus
          value
        end

        def poke(addr, value)
          @tpi.poke(addr, value)
          @machine.update_video_bus
        end
      end
    end
  end
end
