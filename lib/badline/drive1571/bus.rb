# frozen_string_literal: true

module Badline
  class Drive1571
    # The drive CPU's bus:
    #
    # $0000-$07FF - 2 KB of RAM
    # $0800-$17FF - nothing: open bus
    # $1800-$1BFF - VIA 1, its sixteen registers mirrored
    # $1C00-$1FFF - VIA 2, its sixteen registers mirrored
    # $2000-$3FFF - the WD1770, its four registers mirrored
    # $4000-$7FFF - the CIA, its sixteen registers mirrored
    # $8000-$FFFF - the DOS ROM
    #
    # Writes to the ROM and to open bus go nowhere, and a read from open
    # bus finds the last byte on the data bus, as on the 1541. Any access
    # to VIA 2 clears the BYTE READY latch VIA 1's PA7 reads (SerialPort).
    #
    # While Idle records a pass of the DOS's idle loop, the bus watches it,
    # and while Idle looks for an orbit, it guards the drive (see
    # Drive::Watch). Any access to the CIA or the WD1770 makes the pass
    # volatile and taints the drive.
    class Bus
      include Addressable
      include Drive::Watch

      attr_reader :ram, :rom, :via1, :via2, :cia, :fdc, :data

      def initialize(rom:, via1:, via2:, cia:, fdc:)
        addressable_at(0, length: 2**16)
        @ram = Memory.new([], length: 0x0800, start: 0)
        @rom = rom
        @via1 = via1
        @via2 = via2
        @cia = cia
        @fdc = fdc
        @mechanism = via2.mechanism
        @data = 0
        init_watch
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

        watch_read(addr) if @watching
        @data = if addr < 0x0800
                  @ram.peek(addr)
                elsif addr < 0x1800
                  @data
                elsif addr < 0x1c00
                  @via1.peek(addr)
                else
                  @mechanism.release_byte_latch
                  @via2.peek(addr)
                end
      end

      def poke(addr, value)
        @data = value
        return if addr >= 0x8000
        return chip_poke(addr, value) if addr >= 0x2000

        low_poke(addr, value)
      end

      private

      # A write below $2000: RAM or a VIA.
      def low_poke(addr, value)
        if addr < 0x0800
          touch(addr) if @recording
          @ram.poke(addr, value)
        elsif addr >= 0x1c00
          @mechanism.release_byte_latch
          @via2.poke(addr, value)
        elsif addr >= 0x1800
          @via1.poke(addr, value)
        end
        watch_write(addr) if @watching
      end

      def chip_peek(addr)
        watch_chip if @watching
        addr >= 0x4000 ? @cia.peek(0x4000 | (addr & 0x0f)) : @fdc.peek(addr & 0x03)
      end

      def chip_poke(addr, value)
        if addr >= 0x4000
          @cia.poke(0x4000 | (addr & 0x0f), value)
        else
          @fdc.poke(addr & 0x03, value)
        end
        watch_chip if @watching
      end
    end
  end
end
