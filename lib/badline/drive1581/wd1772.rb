# frozen_string_literal: true

require "badline/drive1581/wd1772/registers"
require "badline/drive1581/wd1772/turn"
require "badline/drive1581/wd1772/stepping"
require "badline/drive1581/wd1772/sectors"
require "badline/drive1581/wd1772/sector_writes"
require "badline/drive1581/wd1772/tracks"
require "badline/drive1581/wd1772/state"

module Badline
  class Drive1581
    # The WD1772 floppy disk controller at $6000, as the WD177x data sheet
    # describes it, working on the Mechanism's Track at sector level: it
    # finds ID and data fields where they lie round the turn and moves
    # their bytes at the MFM double-density rate, a byte every 32 µs, but
    # keeps no flux or bitstream.
    #
    #   $6000  status (read), command (write)
    #   $6001  track
    #   $6002  sector
    #   $6003  data
    #
    # It runs on the drive's clock, 2 MHz here, so the data sheet's times,
    # given for 8 MHz on the chip's clock pin, come out as BYTE cycles a
    # byte, STEP_RATES between steps and SETTLE for the head to settle.
    #
    # A command runs as a chain of phases, each due at a cycle (@due): a
    # step, an index pulse, the end of a byte under the head. Between them
    # nothing happens, so cycle! only counts. BUSY sets as the command is
    # written, and the chip takes it up START cycles later, 16 µs, so a
    # command with nothing to do, such as a seek to the track the head is
    # on, still shows BUSY to the DOS, which polls for it before waiting
    # for it to clear.
    #
    # The 1581 leaves INTRQ and DRQ unconnected and polls the status
    # register instead (schematic sheet 2), but both are here (intrq?,
    # drq?). Its DOS sets h in every command, so the motor spin-up wait
    # never runs; the spindle follows the 8520's /MOTOR line instead.
    class WD1772
      include Registers
      include Turn
      include Stepping
      include Sectors
      include SectorWrites
      include Tracks
      include State

      BYTE = 64
      START = 32
      STEP_RATES = [12_000, 24_000, 4_000, 6_000].freeze
      SETTLE = 30_000

      NEVER = 1 << 60

      # Status bits. Bits 1 and 2 report the index pulse and track 0 after
      # a type I command, and DRQ and lost data after the others; bit 5
      # reports spin-up after a type I command and a deleted data mark
      # after a read.
      BUSY = 0x01
      INDEX = 0x02
      DATA_REQUEST = 0x02
      TRACK0 = 0x04
      LOST_DATA = 0x04
      CRC_ERROR = 0x08
      NOT_FOUND = 0x10
      SPUN_UP = 0x20
      DELETED = 0x20
      PROTECTED = 0x40
      MOTOR_ON = 0x80

      # Command flags.
      NO_SPIN_UP = 0x08
      VERIFY = 0x04
      SETTLE_DELAY = 0x04
      MULTIPLE = 0x10
      UPDATE = 0x10
      DELETED_MARK = 0x01

      # Phases.
      IDLE = 0
      SPIN_UP = 1
      STEPPED = 2
      SETTLED = 3
      SEARCH = 4
      READ_DATA = 5
      WRITE_GATE = 6
      WRITE_DATA = 7
      READ_TRACK = 8
      TRACK_INDEX = 9
      WRITE_TRACK = 10
      MOTOR_IDLE = 11
      INDEX_INTERRUPT = 12
      SETTLE_SEARCH = 13
      READ_ADDRESS = 14
      WRITE_TRACK_START = 15
      STARTING = 16

      # What a search for an ID field is for.
      READ = 0
      WRITE = 1
      ADDRESS = 2
      VERIFY_TRACK = 3

      attr_reader :now, :track, :sector, :data, :command

      def initialize(mechanism)
        @mechanism = mechanism
        @now = 0
        @due = NEVER
        @phase = IDLE
        reset!
      end

      # The MR line: the registers as the data sheet leaves them, $03 in
      # the command register and 1 in the sector register, and no command
      # running.
      def reset!
        @command = 0x03
        @track = 0
        @sector = 1
        @data = 0
        @status = 0
        @type1 = true
        @drq = false
        @intrq = false
        @motor_on = false
        @inward = true
        clear_command
        idle
      end

      def cycle!
        @now += 1
        advance if @now == @due
      end

      # How many cycles can go by before the next phase is due.
      def quiet_cycles = @due - @now - 1

      # Runs +cycles+ cycles at once, as many as quiet_cycles allows.
      def fast_forward(cycles)
        @now += cycles
      end

      def busy? = @phase != IDLE && @phase != MOTOR_IDLE && @phase != INDEX_INTERRUPT

      def drq? = @drq

      def intrq? = @intrq

      def motor_on? = @motor_on

      private

      # A command ends: INTRQ, and the motor turns off after nine more
      # index pulses unless a command comes first.
      def finish
        @intrq = true
        @phase = MOTOR_IDLE
        @count = 9
        count_index
      end

      # What a command keeps between its phases.
      def clear_command
        @steps = 0
        @count = 0
        @after_spin_up = IDLE
        @mode = 0
        @deadline = NEVER
        @id_at = NEVER
        @found = -1
        @bytes = []
        @syncs = []
        @index = 0
        @crc = 0xffff
        @crc_good = true
        @write_id = 0
        @size = 0
        @gate_open = false
        @late = false
        @settling = false
      end

      def idle
        @phase = IDLE
        @due = NEVER
      end

      def advance
        case @phase
        when STARTING then start_command
        when SPIN_UP, MOTOR_IDLE, INDEX_INTERRUPT then index_counted
        when STEPPED then step_done
        when SETTLED then verify_track
        when SETTLE_SEARCH then begin_search
        when SEARCH then id_passed
        when READ_DATA, READ_ADDRESS then byte_read
        else advance_write
        end
      end

      def advance_write
        case @phase
        when WRITE_GATE then write_gate
        when WRITE_DATA then byte_written
        when READ_TRACK then track_byte_read
        when TRACK_INDEX then track_index
        when WRITE_TRACK_START then write_track_start
        when WRITE_TRACK then track_byte_written
        end
      end
    end
  end
end
