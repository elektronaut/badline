# frozen_string_literal: true

require "badline/drive1541/rotation"
require "badline/drive1541/mechanism_state"

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
    # The disk turns at 300 rpm under the head, and a read clock at the
    # bit rate PB5-6 select clocks the bits off it (see Rotation).
    #
    # Ten 1 bits in a row are a SYNC mark while CB2 selects reading: PB7
    # reads it, and it holds the bit counter at zero, so the first 0 bit
    # after it starts a byte. Every eighth bit after that is BYTE READY,
    # which pulls VIA 2's CA1 low until the next bit and reaches the CPU's
    # SO pin (see Drive1541#byte_ready!).
    #
    # CB2 low selects write mode, where SYNC detection and the flux are
    # off and the clock runs on at the selected rate. At each BYTE READY
    # the write shift register loads what the VIA drives on port A, and
    # the next eight clocks put that byte's bits on the track, most
    # significant first, in place of what it held. While reading, the load
    # takes the byte just read, so a switch to writing mid-byte writes the
    # rest of it. A write lays its bits one to a cell from the cell under
    # the head, so on a track written at the selected rate each bit fills
    # the cell it passes over. A write to a half track without data gives
    # it a blank track first, a turn long at the selected rate, and a
    # write to a track written at another rate lays the whole track out
    # again as a turn at the selected rate first (Track#relaid).
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
      include Rotation
      include MechanismState

      MOTOR = 0x04
      LED = 0x08
      WRITE_PROTECT = 0x10
      SYNC = 0x80

      MIN_HALF_TRACK = 2
      # Where the head sits at power-on: track 18, the directory.
      START_HALF_TRACK = 36

      SYNC_BITS = 10

      attr_reader :disk, :half_track, :zone

      def initialize(drive)
        @drive = drive
        @disk = nil
        @half_track = START_HALF_TRACK
        @slip = 0
        @motor = false
        @led = false
        @zone = 0
        @clock = Track.cell(0)
        @time = 0
        @clock_at = @clock / 2
        @clocks = 0
        @shift = 0
        @ones = 0
        @bits = 0
        @sync = false
        @byte_ready = false
        @writing = false
        @write_shift = 0
        @write_gate = false
        @protected = false
        load_track
      end

      def motor_on? = @motor

      def led_on? = @led

      def sync? = @sync

      def writing? = @writing

      # What port B and CB2 can change with the motor off: the motor, the
      # LED, the zone and the clock's rate, the stepper, write mode and
      # where a write starts, and the track and cell under the head. The
      # rest moves only while the motor turns, or as a disk goes in (see
      # Drive1541::Idle).
      def idle_state
        [@motor, @led, @zone, @clock, @half_track, @slip, @disk, @track, @index, @mask, @cell_end, @time,
         @writing, @write_index, @sync]
      end

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
        @write_index = nil if high || !@writing
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
          @clock = Track.cell(zone)
          @track_written = false
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

      private

      def read_bit(one)
        if @byte_ready
          @byte_ready = false
          @drive.byte_ready_ended!
        end
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
      def write_bit(at)
        if @byte_ready
          @byte_ready = false
          @drive.byte_ready_ended!
        end
        one = @write_shift.anybits?(0x80)
        @write_shift = (@write_shift << 1) & 0xff
        store_bit(one, at) if @write_gate
        @shift = ((@shift << 1) & 0x3fe) | (one ? 1 : 0)
        @ones = one ? @ones + 1 : 0
        count_bit
      end

      # Each bit written goes in the cell after the last one's, from the
      # cell under the head when the write started.
      def store_bit(one, at)
        track_written(at) unless @track_written
        @write_index ||= (@index * 8) + 8 - @mask.bit_length
        index = @write_index >> 3
        mask = 0x80 >> (@write_index & 7)
        if one
          @bytes[index] |= mask
        else
          @bytes[index] &= ~mask
        end
        @write_index += 1
        @write_index = 0 if @write_index == @length * 8
      end

      # The first write to the track since the head came to it or the rate
      # changed: a half track without data gets a blank track, and a track
      # written at another rate is laid out again at this one.
      def track_written(at)
        track = @disk.writable_track(@half_track, @zone)
        @disk.write(@half_track, track.relaid(@zone)) unless track.written_at?(@zone)
        load_track(at)
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
    end
  end
end
