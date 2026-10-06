# frozen_string_literal: true

module Badline
  class Vic20
    class VIC
      # The VIC's side of the bus, which Vic20::VIC includes. Its address
      # bus has 14 lines, with A13 inverted on the way to the CPU's bus, so
      # the VIC sees $8000-$9FFF at $0000-$1FFF and $0000-$1FFF at
      # $2000-$3FFF. Of those it reaches the character ROM, colour RAM and
      # the 5K of RAM inside the machine, and not the expansion RAM. Every
      # fetch leaves its byte on the V-bus's data lines, and a fetch from an
      # empty spot finds the byte already there.
      module VideoBus
        private

        def page_kind(page)
          return PAGE_ROM if page < 0x10
          return PAGE_COLOR if page >= 0x14 && page < 0x18
          return PAGE_RAM if page >= 0x30 || (page >= 0x20 && page < 0x24)

          PAGE_EMPTY
        end

        # A fetch at +addr+ on the VIC's 14-bit bus, which leaves its byte
        # on the V-bus.
        def video_read(addr)
          bus = @bus
          value = case @pages[addr >> 8]
                  when PAGE_RAM then @ram.peek(addr & 0x1fff)
                  when PAGE_ROM then @character_rom.peek(0x8000 | addr)
                  when PAGE_COLOR then (bus.video_data & 0xf0) | @color_ram.nibble(addr)
                  else bus.video_data
                  end
          bus.video_data = value
          value
        end
      end
    end
  end
end
