# frozen_string_literal: true

module Badline
  module Drives
    class Model8050
      # The interface processor's bus (schematic 8050001, sheet 1). A
      # 74LS42 on A12-A15 picks a 4 KB block:
      #
      # $0000-$0FFF - the two 6532s. A9 is their RS pin and A7 picks one:
      #               UC1's RAM at $00-$7F and UE1's at $80-$FF, mirrored at
      #               $0100 for the stack since A8 isn't decoded, and their
      #               registers at $0200 (UC1) and $0280 (UE1)
      # $1000-$4FFF - the common RAM, 1 KB in each block, mirrored through it
      # $5000-$BFFF - nothing: open bus
      # $C000-$FFFF - DOS 2.7, 901887-01 and 901888-01
      #
      # Writes to the ROM and to open bus go nowhere, and a read from open
      # bus finds the last byte on the data bus.
      class IPBus
        include Addressable

        attr_reader :common, :rom, :data_riot, :control_riot, :data

        # How many writes have changed a byte of the common RAM
        # (Model8050::Idle).
        attr_reader :common_changes

        # Whether a timer or the interrupt flags have been read since it was
        # last cleared (Model8050::Idle).
        attr_accessor :volatile

        def initialize(rom:, common:, data_riot:, control_riot:)
          addressable_at(0, length: 2**16)
          @rom = rom
          @common = common
          @data_riot = data_riot
          @control_riot = control_riot
          @data = 0
          @volatile = false
          @common_changes = 0
        end

        def peek(addr)
          return @data = @rom.peek(addr) if addr >= 0xc000

          @data = if addr < 0x1000
                    peek_riots(addr)
                  elsif addr < 0x5000
                    @common.peek((((addr >> 12) - 1) << 10) | (addr & 0x03ff))
                  else
                    @data
                  end
        end

        def poke(addr, value)
          @data = value
          return if addr >= 0x5000

          if addr < 0x1000
            poke_riots(addr, value)
          else
            poke_common((((addr >> 12) - 1) << 10) | (addr & 0x03ff), value)
          end
        end

        private

        def poke_common(index, value)
          @common_changes += 1 if @common.peek(index) != value
          @common.poke(index, value)
        end

        def peek_riots(addr)
          @volatile = true if addr & 0x204 == 0x204
          if addr.anybits?(0x80)
            addr.anybits?(0x200) ? @control_riot.peek(addr & 0x1f) : @control_riot.read_ram(addr)
          else
            addr.anybits?(0x200) ? @data_riot.peek(addr & 0x1f) : @data_riot.read_ram(addr)
          end
        end

        def poke_riots(addr, value)
          if addr.anybits?(0x80)
            addr.anybits?(0x200) ? @control_riot.poke(addr & 0x1f, value) : @control_riot.write_ram(addr, value)
          else
            addr.anybits?(0x200) ? @data_riot.poke(addr & 0x1f, value) : @data_riot.write_ram(addr, value)
          end
        end
      end
    end
  end
end
