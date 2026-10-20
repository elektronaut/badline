# frozen_string_literal: true

module Badline
  module Drives
    class Model8050
      # The floppy controller's bus (schematic 8050001, sheet 2), which
      # decodes A0-A12 only, so it repeats every 8 KB. A 74LS42 on A10-A12
      # picks a 1 KB block:
      #
      # $0000-$03FF - the 6530 and the VIA: with A7 set the 6530's
      #               registers, else with A6 set the VIA's, else the
      #               6530's 64 bytes of RAM, which the controller also
      #               uses as its stack at $0100
      # $0400-$13FF - the common RAM
      # $1400-$1BFF - nothing: open bus
      # $1C00-$1FFF - the 6530's ROM
      #
      # Writes to the ROM and to open bus go nowhere, and a read from open
      # bus finds the last byte on the data bus.
      class FDCBus
        include Addressable

        attr_reader :common, :via, :rriot
        attr_accessor :data

        # How many writes have changed a byte of the common RAM
        # (Model8050::Idle).
        attr_reader :common_changes

        # Whether a counter or an interrupt flag has been read since it was
        # last cleared (Model8050::Idle).
        attr_accessor :volatile

        # The bytes of the 6530's RAM read or written since it was last
        # cleared, a bit for each pair of them (Model8050::Idle).
        attr_accessor :ram_touched

        def initialize(common:, via:, rriot:)
          addressable_at(0, length: 2**16)
          @common = common
          @via = via
          @rriot = rriot
          @data = 0
          @volatile = false
          @ram_touched = 0
          @common_changes = 0
        end

        def peek(addr)
          addr &= 0x1fff
          @data = if addr < 0x0400
                    peek_chips(addr)
                  elsif addr < 0x1400
                    @common.peek(addr - 0x0400)
                  elsif addr >= 0x1c00
                    @rriot.read_rom(addr)
                  else
                    @data
                  end
        end

        def poke(addr, value)
          @data = value
          addr &= 0x1fff
          if addr < 0x0400
            poke_chips(addr, value)
          elsif addr < 0x1400
            poke_common(addr - 0x0400, value)
          end
        end

        private

        def poke_common(index, value)
          @common_changes += 1 if @common.peek(index) != value
          @common.poke(index, value)
        end

        def peek_chips(addr)
          if addr.anybits?(0x80)
            @volatile = true if addr.anybits?(0x04)
            return @rriot.peek(addr & 0x0f)
          end
          return peek_via(addr & 0x0f) if addr.anybits?(0x40)

          @ram_touched |= 1 << ((addr & 0x3f) >> 1)
          @rriot.read_ram(addr)
        end

        # The VIA's counters, shift register and flags move on their own.
        def peek_via(register)
          @volatile = true if register.between?(0x04, 0x0a) || register == 0x0d
          @via.peek(0x40 | register)
        end

        def poke_chips(addr, value)
          if addr.anybits?(0x80)
            @rriot.poke(addr & 0x0f, value)
          elsif addr.anybits?(0x40)
            @via.poke(0x40 | (addr & 0x0f), value)
          else
            @ram_touched |= 1 << ((addr & 0x3f) >> 1)
            @rriot.write_ram(addr, value)
          end
        end
      end
    end
  end
end
