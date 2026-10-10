# frozen_string_literal: true

module Badline
  class Drive1581
    # The 1581's 3.5" mechanism: the spindle motor, the head on one of
    # its cylinders and sides, the index sensor, and the lines it reports
    # on the drive connector (1581 Service Manual, schematic sheet 2).
    #
    # The motor runs while /MOTOR is low and turns a disk at 300 rpm, a
    # turn every REVOLUTION drive cycles at 2 MHz. The index sensor pulses
    # for INDEX_PULSE cycles at the start of each turn, which is where a
    # Track's bytes start. /RDY is low while the motor turns a disk. The
    # WD1772 steps the head, and /TR00 is low while it sits on cylinder 0.
    # /WPRT is low while the disk's write-protect hole is open, or without
    # a disk.
    #
    # /DISK CHNG goes low as a disk comes out, and at power-on, and goes
    # high again at a step pulse with a disk in, as on any Shugart-style
    # drive with a disk change line. The DOS steps in and out after
    # spinning the motor up to find out whether a disk is in.
    #
    # Times are the WD1772's cycle count (WD1772#now), which the drive
    # passes in: the angle under the head follows from how long the disk
    # has turned.
    class Mechanism
      REVOLUTION = 400_000
      INDEX_PULSE = 4_000
      LAST_CYLINDER = 83

      attr_reader :disk, :cylinder
      attr_accessor :side

      def initialize
        @disk = nil
        @cylinder = 0
        @side = 0
        @motor = false
        @changed = true
        @angle = 0
        @since = 0
      end

      # Puts a Disk in, or with nil takes it out. Whatever was in is
      # flushed first, and the disk change line goes low.
      def insert(disk, now)
        @angle = angle(now)
        @since = now
        flush
        @disk = disk
        @changed = true
      end

      def flush = @disk&.flush

      def motor_on? = @motor

      # Turns the motor on or off at +now+.
      def motor(on, now)
        @angle = angle(now)
        @since = now
        @motor = on
      end

      # Whether a disk turns.
      def spinning? = @motor && !@disk.nil?

      # How far into its turn the disk is at +now+, in cycles from the
      # index.
      def angle(now) = spinning? ? (@angle + now - @since) % REVOLUTION : @angle

      def index?(now) = spinning? && angle(now) < INDEX_PULSE

      def ready? = spinning?

      def track0? = @cylinder.zero?

      def disk_changed? = @changed

      def write_protected? = @disk.nil? || @disk.write_protected?

      # A step pulse, towards the hub with +inward+.
      def step(inward)
        @cylinder = (@cylinder + (inward ? 1 : -1)).clamp(0, LAST_CYLINDER)
        @changed = false if @disk
      end

      # The Track under the head, or nil.
      def track = @disk&.track(@cylinder, @side)

      # Stores a track the WD1772 laid down under the head.
      def write(track)
        @disk&.write(@cylinder, @side, track)
      end

      # The disk (Disk#save_state) and the motor, the head and the turn.
      def save_state(out)
        out.boolean(!@disk.nil?)
        @disk&.save_state(out)
        out.int(@cylinder).int(@side).int(@angle).int(@since).boolean(@motor).boolean(@changed)
      end

      # Puts the state back, reusing the disk in when it's the one the state
      # names (Disk::SavedState.load). A disk taken out is flushed.
      def load_state(input)
        disk = input.boolean? ? Disk::SavedState.load(input, @disk) : nil
        flush unless disk.equal?(@disk)
        @disk = disk
        @cylinder = input.int
        @side = input.int
        @angle = input.int
        @since = input.int
        @motor = input.boolean?
        @changed = input.boolean?
      end
    end
  end
end
