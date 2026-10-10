# frozen_string_literal: true

module Badline
  class Drive1581
    # The drive CPU's bus, as the 74LS139 decodes A13-A15 (1581 Service
    # Manual, memory map and schematic sheet 1):
    #
    # $0000-$1FFF - 8 KB of RAM
    # $2000-$3FFF - nothing: open bus
    # $4000-$5FFF - the 8520, its sixteen registers mirrored
    # $6000-$7FFF - the WD1772, its four registers mirrored
    # $8000-$FFFF - the DOS ROM
    #
    # Writes to the ROM and to open bus go nowhere, and a read from open
    # bus finds the last byte on the data bus, as on the 1541. A write to
    # either of the 8520's ports or their direction registers moves the
    # drive's lines (Drive1581#ports_written).
    #
    # While Idle records a pass of the DOS's idle loop, the bus watches it
    # (watch!): the RAM it reads and writes, and whether it touched the
    # 8520 or the WD1772, either of which makes the pass volatile. While
    # Idle looks for an orbit, the bus guards the drive (guard!), and any
    # access to either chip taints it.
    class Bus
      include Addressable

      attr_reader :ram, :rom, :cia, :fdc, :data, :volatile, :touched, :tainted, :touched_timers

      def initialize(rom:, cia:, fdc:, drive:)
        addressable_at(0, length: 2**16)
        @ram = Memory.new([], length: 0x2000, start: 0)
        @rom = rom
        @cia = cia
        @fdc = fdc
        @drive = drive
        @data = 0
        @recording = @guarding = @watching = false
        @volatile = @tainted = false
        @touched = {}
        @touched_timers = 0
      end

      # The last byte on the data bus and the RAM. What a watched stretch
      # touched is Idle's, and a restored bus isn't watching.
      def save_state(out)
        out.int(@data)
        @ram.save_state(out)
      end

      def load_state(input)
        @data = input.int
        @ram.load_state(input)
        @watching = false
      end

      def peek(addr)
        return @data = @rom.peek(addr) if addr >= 0x8000
        return @data = chip_peek(addr) if addr >= 0x2000

        touch(addr) if @recording
        @data = @ram.peek(addr)
      end

      def poke(addr, value)
        @data = value
        return if addr >= 0x8000
        return chip_poke(addr, value) if addr >= 0x2000

        touch(addr) if @recording
        @ram.poke(addr, value)
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

      private

      def chip_peek(addr)
        watch_chip if @watching
        if addr >= 0x6000
          @fdc.peek(addr & 0x03)
        elsif addr >= 0x4000
          @cia.peek(0x4000 | (addr & 0x0f))
        else
          @data
        end
      end

      def chip_poke(addr, value)
        watch_chip if @watching
        if addr >= 0x6000
          @fdc.poke(addr & 0x03, value)
        elsif addr >= 0x4000
          @cia.poke(0x4000 | (addr & 0x0f), value)
          @drive.ports_written if addr.nobits?(0x0c)
        end
      end

      def touch(addr)
        @touched[addr] = @ram.peek(addr) unless @touched.key?(addr)
      end

      def watching!
        @watching = @recording || @guarding
      end

      def watch_chip
        if @recording
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
