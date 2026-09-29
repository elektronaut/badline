# frozen_string_literal: true

module Badline
  class Drive1541
    # The drive CPU's bus. The decoder looks at A15, A12, A11 and A10 only:
    #
    # $0000-$07FF - 2 KB of RAM
    # $0800-$17FF - nothing: open bus
    # $1800-$1BFF - VIA 1, its sixteen registers mirrored
    # $1C00-$1FFF - VIA 2, its sixteen registers mirrored
    # $2000-$7FFF - $0000-$1FFF again, since A13 and A14 aren't decoded
    # $8000-$BFFF - the ROM again, since A14 isn't decoded
    # $C000-$FFFF - the DOS ROM
    #
    # Writes to the ROM and to open bus go nowhere. A read from open bus
    # finds the last byte on the data bus, which for LDA abs or LDA (zp),Y
    # is the address's high byte, and for an indexed read that crosses a
    # page is what its dummy read found. VICE-testprogs drive/openbus pins
    # both on a real 1541.
    #
    # While Idle records a pass of the DOS's idle loop, the bus watches it
    # (see watch!). While Idle looks for an orbit, the bus guards the drive
    # (see guard!).
    class Bus
      include Addressable

      # VIA registers, as bits by offset, whose access makes a watched
      # stretch volatile: reads of either VIA's counters and shift register
      # and of VIA 1's port B, and writes to VIA 2's timers, shift register
      # and ACR. Any write to VIA 1 does too (watch_write).
      VOLATILE_VIA1_READS = 0x0731
      VOLATILE_VIA2_READS = 0x0730
      VOLATILE_VIA2_WRITES = 0x0ff0

      # The timer each VIA register reaches, by offset, as bits: 1 for
      # timer 1 and 2 for timer 2.
      TIMER_REGISTERS = [0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 0, 0, 0, 0, 0, 0].freeze

      attr_reader :ram, :rom, :via1, :via2, :data

      # Whether a watched stretch did something that makes it unrepeatable.
      attr_reader :volatile

      # The RAM a watched stretch read or wrote, as each address's value
      # from before the first access.
      attr_reader :touched

      # Whether the drive did something since guard! that reached outside
      # it, or took something in from outside.
      attr_reader :tainted

      # The timers the drive read or wrote since guard!, as bits: VIA 1's
      # timer 1 and timer 2 in bits 0 and 1, and VIA 2's in bits 2 and 3.
      attr_reader :touched_timers

      def initialize(rom:, via1:, via2:)
        addressable_at(0, length: 2**16)
        @ram = Memory.new([], length: 0x0800, start: 0)
        @rom = rom
        @via1 = via1
        @via2 = via2
        @data = 0
        @recording = @guarding = @watching = false
        @volatile = @tainted = false
        @touched = {}
        @touched_timers = 0
        @led = 0
      end

      # Starts watching: see volatile and touched. The bus stops watching
      # once the stretch turns volatile.
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

      # Starts guarding: see tainted and touched_timers. Reading VIA 1's
      # port B, which reads the serial bus, taints the drive, and so do
      # any write to VIA 1, whose port B drives the serial bus, a write to
      # VIA 2's shift register or ACR, and VIA 2 turning the motor on or
      # changing the LED. The bus stops guarding once the drive is tainted.
      def guard!
        @guarding = true
        @tainted = false
        @touched_timers = 0
        @led = @via2.port_b_output & Mechanism::LED
        watching!
      end

      def peek(addr)
        return @data = @rom.peek(addr | 0x4000) if addr >= 0x8000

        addr &= 0x1fff
        watch_read(addr) if @watching
        @data = if addr < 0x0800
                  @ram.peek(addr)
                elsif addr < 0x1800
                  @data
                elsif addr < 0x1c00
                  @via1.peek(addr)
                else
                  @via2.peek(addr)
                end
      end

      def poke(addr, value)
        @data = value
        return if addr >= 0x8000

        addr &= 0x1fff
        if addr < 0x0800
          touch(addr) if @recording
          @ram.poke(addr, value)
        elsif addr >= 0x1c00
          @via2.poke(addr, value)
        elsif addr >= 0x1800
          @via1.poke(addr, value)
        end
        watch_write(addr) if @watching
      end

      private

      def watching!
        @watching = @recording || @guarding
      end

      def touch(addr)
        @touched[addr] = @ram.peek(addr) unless @touched.key?(addr)
      end

      def watch_read(addr)
        if addr < 0x0800
          touch(addr) if @recording
        elsif addr >= 0x1800
          via1 = addr < 0x1c00
          watch(via1 ? VOLATILE_VIA1_READS : VOLATILE_VIA2_READS, addr) if @recording
          guard_read(via1, addr & 0x0f) if @guarding
        end
      end

      def watch_write(addr)
        if addr >= 0x1c00
          watch_via2_write(addr) if @recording
          guard_via2_write(addr & 0x0f) if @guarding
        elsif addr >= 0x1800
          volatile! if @recording
          taint! if @guarding
        end
      end

      # Any write to VIA 1 makes the stretch volatile (watch_write), and so
      # does a write to VIA 2 that leaves the motor on.
      def watch_via2_write(addr)
        watch(VOLATILE_VIA2_WRITES, addr)
        volatile! if @recording && @via2.port_b_output.anybits?(Mechanism::MOTOR)
      end

      def watch(volatile, addr)
        volatile! if volatile.anybits?(1 << (addr & 0x0f))
      end

      def volatile!
        @volatile = true
        @recording = false
        watching!
      end

      def guard_read(via1, offset)
        return taint! if via1 && offset.zero?

        @touched_timers |= via1 ? TIMER_REGISTERS[offset] : TIMER_REGISTERS[offset] << 2
      end

      def guard_via2_write(offset)
        return taint! if offset.between?(0x0a, 0x0b)

        @touched_timers |= TIMER_REGISTERS[offset] << 2
        lines = @via2.port_b_output
        taint! if lines.anybits?(Mechanism::MOTOR) || (lines & Mechanism::LED) != @led
      end

      def taint!
        @tainted = true
        @guarding = false
        watching!
      end
    end
  end
end
