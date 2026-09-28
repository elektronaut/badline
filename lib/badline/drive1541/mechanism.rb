# frozen_string_literal: true

module Badline
  class Drive1541
    # The disk mechanism behind VIA 2: the spindle motor, the head on its
    # stepper, the LED and the read electronics.
    #
    # Port B drives it and reads it back:
    #
    #   PB0-1  stepper phase (out)    PB4    write protect (in, 1 = writable)
    #   PB2    motor on (out)         PB5-6  bit rate, speed zone 0-3 (out)
    #   PB3    LED on (out)           PB7    SYNC (in, 0 while in a SYNC mark)
    #
    # Port A reads the read shift register's low eight bits, which CA1
    # latches on BYTE READY.
    #
    # The head reads the track under it, bit after bit, while the motor
    # turns, at the rate PB5-6 select: a bit every 4 * (16 - zone) ticks of
    # the drive's 16 MHz crystal, so a byte every 32, 30, 28 or 26 drive
    # cycles in zones 0 to 3. A disk turns once in a track's length of
    # bytes, 200 ms at the rate its zone was written at. Ten 1 bits in a
    # row are a SYNC mark while CB2 selects reading: PB7 reads it, and it
    # holds the bit counter at zero, so the first 0 bit after it starts a
    # byte. Every eighth bit after that is BYTE READY, which pulls VIA 2's
    # CA1 low until the next bit and reaches the CPU's SO pin (see
    # Drive1541#byte_ready!).
    #
    # The stepper moves the head a half track each time the phase steps
    # by one, inwards for +1 and outwards for -1. Each half track has a
    # phase of its own, from power-on the low two bits of its number, so
    # the head sits on a whole track when phase 0 or 2 holds it. The
    # stepper's coils are powered only while PB2 runs the motor, as VICE
    # reads the 1541's schematic, so a phase set with the motor off moves
    # nothing until the motor comes on and it pulls the head. Tracks run
    # from half track 2 (track 1), where the head stops against the end of
    # its rail, to Disk::MAX_HALF_TRACK. A step out against the stop slips:
    # the head stays on track 1 and the phase that tried to pull it out
    # becomes track 1's, so the DOS's bump leaves the head on track 1 in
    # line with the phase it ends on, and its first step in reaches the
    # half track after it.
    class Mechanism
      MOTOR = 0x04
      LED = 0x08
      WRITE_PROTECT = 0x10
      SYNC = 0x80

      MIN_HALF_TRACK = 2
      # Where the head sits at power-on: track 18, the directory.
      START_HALF_TRACK = 36

      TICKS_PER_CYCLE = 16
      SYNC_BITS = 10

      # What the head reads with no disk in, or off the tracks a disk has:
      # no flux, so only 0 bits and no SYNC.
      BLANK = Array.new(Disk::TRACK_LENGTHS[0], 0).freeze

      attr_reader :disk, :half_track, :zone

      def initialize(drive)
        @drive = drive
        @disk = nil
        @half_track = START_HALF_TRACK
        @slip = 0
        @motor = false
        @led = false
        @zone = 0
        @bit_ticks = bit_ticks(0)
        @ticks = @bit_ticks
        @shift = 0
        @ones = 0
        @bits = 0
        @sync = false
        @byte_ready = false
        @bytes = BLANK
        @index = 0
        @mask = 0x80
      end

      def motor_on? = @motor

      def led_on? = @led

      def sync? = @sync

      # Puts a Disk in, or takes it out with nil. The head goes on from the
      # same point in the turn.
      def insert(disk)
        @disk = disk
        load_track
      end

      # VIA 2 drives port B's lines to +lines+.
      def port_b_written(lines)
        @motor = lines.anybits?(MOTOR)
        @led = lines.anybits?(LED)
        zone = (lines >> 5) & 0x03
        if zone != @zone
          @zone = zone
          @bit_ticks = bit_ticks(zone)
        end
        step(lines & 0x03) if @motor
      end

      # Port A is the read shift register.
      def read_a(_lines) = @shift & 0xff

      # SYNC low in a SYNC mark, and the disk writable.
      def read_b(_lines) = @sync ? 0xff & ~SYNC : 0xff

      # One drive cycle: nothing with the motor off, and otherwise a bit
      # whenever one has passed under the head.
      def cycle!
        return unless @motor

        @ticks -= TICKS_PER_CYCLE
        return if @ticks.positive?

        @ticks += @bit_ticks
        read_bit
      end

      private

      def bit_ticks(zone) = 4 * (16 - zone)

      def read_bit
        if @byte_ready
          @byte_ready = false
          @drive.byte_ready_ended!
        end
        one = @bytes[@index].anybits?(@mask)
        advance
        @shift = ((@shift << 1) & 0x3fe) | (one ? 1 : 0)
        if one
          @ones += 1
          @sync = true if @ones >= SYNC_BITS && @drive.via2.cb2_output
        else
          @ones = 0
          @sync = false
        end
        count_bit
      end

      def count_bit
        if @sync
          @bits = 0
          return
        end
        @bits += 1
        return unless @bits == 8

        @bits = 0
        @byte_ready = true
        @drive.byte_ready!
      end

      def advance
        @mask >>= 1
        return unless @mask.zero?

        @mask = 0x80
        @index += 1
        @index = 0 if @index == @bytes.length
      end

      # The stepper's rotor turns with the head, a phase to each half
      # track, so the energized phase pulls the head to the neighbouring
      # half track it belongs to. A phase two away pulls both ways, and the
      # head stays. Against the stop at track 1 the head can't follow, and
      # the phases slip round to where the head is.
      def step(phase)
        move = (phase - @half_track - @slip) & 0x03
        if move == 1
          seek(@half_track + 1)
        elsif move == 3 && @half_track == MIN_HALF_TRACK
          @slip = (phase - MIN_HALF_TRACK) & 0x03
        elsif move == 3
          seek(@half_track - 1)
        end
      end

      def seek(half_track)
        half_track = half_track.clamp(MIN_HALF_TRACK, Disk::MAX_HALF_TRACK)
        return if half_track == @half_track

        @half_track = half_track
        load_track
      end

      # The new track's bytes, from the same angle as the head left the
      # last one, since tracks differ in length.
      def load_track
        track = @disk&.track(@half_track)
        bytes = track ? track.bytes : BLANK
        @index = @index * bytes.length / @bytes.length
        @bytes = bytes
      end
    end
  end
end
