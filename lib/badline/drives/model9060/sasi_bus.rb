# frozen_string_literal: true

module Badline
  module Drives
    class Model9060
      # The SASI host processor's bus on the DOS board (300010), where the
      # 8050's floppy controller sits, with its decode and common RAM:
      #
      # $0000-$007F - the 6810's 128 bytes, mirrored at $0100 for the stack
      # $0080-$008F - the VIA (SASILines)
      # $0400-$13FF - the common RAM, 1 KB in each of the 8050's windows
      # $F800-$FFFF - 300515, the host's program
      #
      # Writes to the ROM and to open bus go nowhere, and a read from open
      # bus finds the last byte on the data bus.
      class SASIBus
        include Addressable

        attr_reader :common, :ram, :via
        attr_accessor :data

        # How many writes have changed a byte of the common RAM
        # (Model9060::Idle).
        attr_reader :common_changes

        # Whether a counter or an interrupt flag has been read since it was
        # last cleared (Model9060::Idle).
        attr_accessor :volatile

        def initialize(rom:, common:, via:)
          addressable_at(0, length: 2**16)
          @rom = rom
          @common = common
          @via = via
          @ram = Memory.new([], length: 0x80)
          @data = 0
          @volatile = false
          @common_changes = 0
        end

        def peek(addr)
          @data = if addr >= 0xf800
                    @rom.peek(addr & 0x07ff)
                  elsif addr < 0x0200
                    peek_low(addr)
                  elsif addr.between?(0x0400, 0x13ff)
                    @common.peek(addr - 0x0400)
                  else
                    @data
                  end
        end

        def poke(addr, value)
          @data = value
          if addr < 0x0200
            poke_low(addr, value)
          elsif addr.between?(0x0400, 0x13ff)
            poke_common(addr - 0x0400, value)
          end
        end

        private

        def peek_low(addr)
          return @ram.peek(addr & 0x7f) if addr.nobits?(0x80)
          return @data if addr.anybits?(0x70)

          register = addr & 0x0f
          @volatile = true if register.between?(0x04, 0x0a) || register == 0x0d
          @via.peek(0x80 | register)
        end

        def poke_low(addr, value)
          if addr.nobits?(0x80)
            @ram.poke(addr & 0x7f, value)
          elsif addr.nobits?(0x70)
            @via.poke(0x80 | (addr & 0x0f), value)
          end
        end

        def poke_common(index, value)
          @common_changes += 1 if @common.peek(index) != value
          @common.poke(index, value)
        end
      end
    end
  end
end
