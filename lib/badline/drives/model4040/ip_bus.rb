# frozen_string_literal: true

module Badline
  module Drives
    class Model4040
      # The interface processor's bus (schematic 320806, sheet 1). UB3
      # decodes A12-A14 only, so the map repeats every 32 KB:
      #
      # $0000-$0FFF - the two 6532s, as on the 8050 (Model8050::IPBus)
      # $1000-$4FFF - the common RAM, 1 KB in each block, mirrored through it
      # $5000-$7FFF - the ROM sockets UJ1, UL1 and UH1, seen again at
      #               $D000-$FFFF, where the processor finds its vectors
      #
      # A socket left empty, as UJ1 is under DOS 1, reads as open bus: the
      # last byte on the data bus.
      class IPBus < Model8050::IPBus
        def peek(addr)
          addr &= 0x7fff
          return @data = rom_peek(addr | 0x8000) if addr >= 0x5000

          @data = if addr < 0x1000
                    peek_riots(addr)
                  else
                    @common.peek((((addr >> 12) - 1) << 10) | (addr & 0x03ff))
                  end
        end

        def poke(addr, value)
          @data = value
          addr &= 0x7fff
          return if addr >= 0x5000

          if addr < 0x1000
            poke_riots(addr, value)
          else
            poke_common((((addr >> 12) - 1) << 10) | (addr & 0x03ff), value)
          end
        end

        private

        def rom_peek(addr) = addr >= @rom.start ? @rom.peek(addr) : @data
      end
    end
  end
end
