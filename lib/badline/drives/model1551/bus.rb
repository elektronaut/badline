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
      #
      # While Engine::Idle records a pass of the DOS's idle loop, the bus
      # watches it (watch!): the RAM it reads and writes, and whether it
      # reached the port or the TIA, which makes the pass volatile, but for
      # reads of the TIA's port A, the cable's data lines, which hold still
      # until the computer moves them. While Engine::Orbit looks for an
      # orbit, the bus guards the drive (guard!), and any access to the
      # port or the TIA taints it.
      class Bus
        include Addressable

        attr_reader :ram, :rom, :port, :tia, :data, :volatile, :touched, :tainted, :touched_timers

        def initialize(rom:, port:, tia:)
          addressable_at(0, length: 2**16)
          @ram = Memory.new([], length: 0x0800, start: 0)
          @rom = rom
          @port = port
          @tia = tia
          @data = 0
          @recording = @guarding = @watching = false
          @volatile = @tainted = false
          @touched = {}
          @touched_timers = 0
        end

        def peek(addr)
          return @data = @rom.peek(addr) if addr >= 0xc000

          if addr < 0x0800
            return @data = port_peek(addr) if addr < 2

            touch(addr) if @recording
            return @data = @ram.peek(addr)
          end
          return @data unless addr.between?(0x4000, 0x7fff)

          watch_chip(addr.nobits?(0x07)) if @watching
          @data = @tia.peek(addr)
        end

        def poke(addr, value)
          @data = value
          if addr < 0x0800
            return port_poke(addr, value) if addr < 2

            touch(addr) if @recording
            @ram.poke(addr, value)
          elsif addr.between?(0x4000, 0x7fff)
            watch_chip(false) if @watching
            @tia.poke(addr, value)
          end
        end

        # Starts watching: see volatile and touched.
        def watch!
          @recording = true
          @volatile = false
          @touched = {}
          watching!
        end

        def unwatch!
          @recording = false
          watching!
        end

        # Starts guarding: see tainted.
        def guard!
          @guarding = true
          @tainted = false
          watching!
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
          @watching = false
        end

        private

        def port_peek(addr)
          watch_chip(false) if @watching
          @port.peek(addr)
        end

        def port_poke(addr, value)
          watch_chip(false) if @watching
          @port.poke(addr, value)
        end

        def touch(addr)
          @touched[addr] = @ram.peek(addr) unless @touched.key?(addr)
        end

        def watching!
          @watching = @recording || @guarding
        end

        # The CPU reached the port or the TIA: +steady+ for a read of the
        # TIA's port A.
        def watch_chip(steady)
          if @recording && !steady
            @volatile = true
            @recording = false
          end
          if @guarding
            @tainted = true
            @guarding = false
          end
          watching!
        end
      end
    end
  end
end
