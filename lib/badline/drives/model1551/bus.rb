# frozen_string_literal: true

module Badline
  module Drives
    class Model1551
      # The drive CPU's bus, as the gate array decodes it (schematic 251860):
      #
      # $0000-$0001 - the 6510T's port (Port)
      # $0002-$07FF - 2 KB of RAM
      # $4000-$7FFF - the TIA, its eight registers mirrored
      # $C000-$FFFF - the DOS ROM
      #
      # Writes to the ROM and to the rest go nowhere, and a read from the
      # rest finds the last byte on the data bus.
      class Bus
        include Addressable

        attr_reader :ram, :rom, :port, :tia, :data

        def initialize(rom:, port:, tia:)
          addressable_at(0, length: 2**16)
          @ram = Memory.new([], length: 0x0800, start: 0)
          @rom = rom
          @port = port
          @tia = tia
          @data = 0
        end

        def peek(addr)
          @data = if addr >= 0xc000
                    @rom.peek(addr)
                  elsif addr < 0x0800
                    addr < 2 ? @port.peek(addr) : @ram.peek(addr)
                  elsif addr.between?(0x4000, 0x7fff)
                    @tia.peek(addr)
                  else
                    @data
                  end
        end

        def poke(addr, value)
          @data = value
          if addr < 0x0800
            addr < 2 ? @port.poke(addr, value) : @ram.poke(addr, value)
          elsif addr.between?(0x4000, 0x7fff)
            @tia.poke(addr, value)
          end
        end

        # The drive's RAM and the byte last on its data bus, in a keyed
        # snapshot module (BL-D8-RAM).
        def save_fields(out)
          out.int("data", @data).bytes("ram", @ram.read(0, @ram.length))
        end

        def load_fields(input)
          @data = input.byte("data", @data)
          ram = @ram.read(0, @ram.length)
          @ram.write(0, input.bytes_into("ram", ram))
        end
      end
    end
  end
end
