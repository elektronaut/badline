# frozen_string_literal: true

module Badline
  class Drive1541
    # The disk mechanism behind VIA 2: the spindle motor, the head on its
    # stepper, the LED, the read and write electronics and the
    # write-protect sensor.
    #
    # Port B drives it and reads it back:
    #
    #   PB0-1  stepper phase (out)    PB4    write protect (in, 1 = writable)
    #   PB2    motor on (out)         PB5-6  bit rate, speed zone 0-3 (out)
    #   PB3    LED on (out)           PB7    SYNC (in, 0 while in a SYNC mark)
    #
    # Port A reads the read shift register's low eight bits, which CA1
    # latches on BYTE READY. In write mode it drives the write shift
    # register, and the read shift register takes the bits written.
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
    # CB2 low selects write mode, where SYNC detection is off. At each
    # BYTE READY the write shift register loads what the VIA drives on
    # port A, and the next eight bits the head passes over are that
    # byte's, most significant first, in place of what the track held.
    # While reading, the load takes the byte just read, so a switch to
    # writing mid-byte writes the rest of it. A write to a half track
    # without data gives it a blank track, a turn long at the bit rate
    # it's written at.
    #
    # PB4 reads the write-protect sensor: high with no disk in, or with
    # the notch of a writable one open. With the disk write-protected the
    # write gate stays shut: the bits and BYTE READY go on, and nothing
    # reaches the disk. The DOS reads PB4 first and refuses to write, so
    # only a program that writes without asking finds that out.
    #
    # The motor stopping flushes what was written to the disk's image
    # (see Disk#flush), which is when the DOS is done with a job, and so
    # does taking the disk out.
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
      # no flux, so only 0 bits and no SYNC, for a turn at the bit rate of
      # each zone. Without flux there's nothing to set the length of a
      # turn but the rate the bits are clocked at, so a turn over blank
      # disk takes 200 ms, as it does over a track, whatever the zone.
      BLANKS = Disk::TRACK_LENGTHS.map { |length| Array.new(length, 0).freeze }.freeze

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
        @bytes = BLANKS[0]
        @index = 0
        @mask = 0x80
        @writing = false
        @write_shift = 0
        @write_gate = false
        @protected = false
      end

      def motor_on? = @motor

      def led_on? = @led

      def sync? = @sync

      def writing? = @writing

      # Puts a Disk in, or takes it out with nil, flushing the disk that
      # was in. The head goes on from the same point in the turn.
      def insert(disk)
        flush
        @disk = disk
        @protected = disk&.write_protected? || false
        @write_gate = !disk.nil? && !@protected
        load_track
      end

      # Stores what the head wrote in the disk's image.
      def flush
        @disk.flush if @disk&.written?
      rescue Storage::WriteError => e
        warn "1541: couldn't write the disk back: #{e.message}"
      end

      # VIA 2 drives CB2 to +high+: low selects write mode, which stops
      # SYNC detection at once.
      def cb2_written(high)
        @writing = !high
        @sync = !@writing && @ones >= SYNC_BITS
      end

      # VIA 2 drives port B's lines to +lines+.
      def port_b_written(lines)
        motor = @motor
        @motor = lines.anybits?(MOTOR)
        flush if motor && !@motor
        @led = lines.anybits?(LED)
        zone = (lines >> 5) & 0x03
        if zone != @zone
          @zone = zone
          @bit_ticks = bit_ticks(zone)
          load_track if @bytes.frozen?
        end
        step(lines & 0x03) if @motor
      end

      # Port A is the read shift register.
      def read_a(_lines) = @shift & 0xff

      # SYNC low in a SYNC mark, and write protect low for a protected
      # disk.
      def read_b(_lines)
        lines = @sync ? 0xff & ~SYNC : 0xff
        @protected ? lines & ~WRITE_PROTECT : lines
      end

      # One drive cycle: nothing with the motor off, and otherwise a bit
      # whenever one has passed under the head.
      def cycle!
        return unless @motor

        @ticks -= TICKS_PER_CYCLE
        return if @ticks.positive?

        @ticks += @bit_ticks
        @writing ? write_bit : read_bit
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
          @sync = true if @ones >= SYNC_BITS
        else
          @ones = 0
          @sync = false
        end
        count_bit
      end

      # The write shift register's top bit goes onto the track through the
      # write gate, and into the read shift register, as the head's own
      # signal.
      def write_bit
        if @byte_ready
          @byte_ready = false
          @drive.byte_ready_ended!
        end
        one = @write_shift.anybits?(0x80)
        @write_shift = (@write_shift << 1) & 0xff
        store_bit(one) if @write_gate
        advance
        @shift = ((@shift << 1) & 0x3fe) | (one ? 1 : 0)
        @ones = one ? @ones + 1 : 0
        count_bit
      end

      def store_bit(one)
        track_written if @bytes.frozen? || !@track_written
        if one
          @bytes[@index] |= @mask
        else
          @bytes[@index] &= ~@mask
        end
      end

      # The first write to the track since the head came to it: a half
      # track without data gets a blank one to write on, a turn long at
      # the bit rate it's written at.
      def track_written
        if @bytes.frozen?
          @disk.writable_track(@half_track, @zone)
          load_track
        end
        @disk.written(@half_track)
        @track_written = true
      end

      # Every eighth bit outside a SYNC mark is BYTE READY, which loads the
      # write shift register: from what the VIA drives on port A in write
      # mode, and with the byte just read otherwise.
      def count_bit
        if @sync
          @bits = 0
          return
        end
        @bits += 1
        return unless @bits == 8

        @bits = 0
        @write_shift = @writing ? @drive.via2.port_a_output : @shift & 0xff
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
        bytes = track ? track.bytes : BLANKS[@zone]
        @index = @index * bytes.length / @bytes.length
        @bytes = bytes
        @track_written = false
      end
    end
  end
end
