# frozen_string_literal: true

module Badline
  module Drive
    # A drive bus's eye on what the CPU reaches, for Idle and Orbit. While
    # Idle records a pass of the DOS's idle loop, the bus watches it (see
    # watch!). While Idle looks for an orbit, the bus guards the drive
    # (see guard!). The bus calls watch_read and watch_write with the
    # address folded into $0000-$1FFF, RAM and the two VIAs at $1800 and
    # $1C00, while @watching.
    module Watch
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
        @led = @via2.port_b_output & Drive1541::Mechanism::LED
        watching!
      end

      private

      def init_watch
        @recording = @guarding = @watching = false
        @volatile = @tainted = false
        @touched = {}
        @touched_timers = 0
        @led = 0
      end

      def watching!
        @watching = @recording || @guarding
      end

      # An access to a chip beyond the VIAs, as the 1571's CIA and floppy
      # controller are: it makes the stretch volatile and taints the
      # drive.
      def watch_chip
        volatile! if @recording
        taint! if @guarding
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
        volatile! if @recording && @via2.port_b_output.anybits?(Drive1541::Mechanism::MOTOR)
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
        taint! if lines.anybits?(Drive1541::Mechanism::MOTOR) || (lines & Drive1541::Mechanism::LED) != @led
      end

      def taint!
        @tainted = true
        @guarding = false
        watching!
      end
    end
  end
end
