# frozen_string_literal: true

module Badline
  class Drive1571
    # The WD1770 floppy controller at $2000, which DOS 3.0 drives for MFM
    # disks. The 1571 here only ever holds GCR disks, so the controller
    # never finds an MFM sector: it runs each command for its time and ends
    # it as the WD177x data sheet does on a disk without one.
    #
    #   $2000  status (read), command (write)
    #   $2001  track
    #   $2002  sector
    #   $2003  data
    #
    # BUSY sets as a command is written. A restore, seek or step (type I)
    # moves the track register and ends a few milliseconds later, with
    # TRACK 0 reported at track 0. A sector read or write, a read address
    # or a read track ends with RECORD NOT FOUND after five turns of the
    # disk, and a write track after one, with nothing written. A force
    # interrupt ends the command at once. Time is the drive CPU's cycles.
    class WD1770
      BUSY = 0x01
      TRACK0 = 0x04
      NOT_FOUND = 0x10
      MOTOR_ON = 0x80

      # Cycles at 2 MHz, the 1571's clock in 1571 mode: a turn of the disk
      # at 300 rpm, and a step with the head settling.
      TURN = 400_000
      STEP = 12_000

      # The CPU whose cycles time the commands.
      attr_writer :cpu

      def initialize
        @registers = [0, 0, 0, 0]
        @status = 0
        @due = 0
        @result = 0
        @cpu = nil
      end

      # Register +offset+, 0 to 3: the status, settled to the command's end
      # once its time has run out.
      def peek(offset)
        return @registers[offset] unless offset.zero?

        finish if @status.anybits?(BUSY) && @cpu.cycles >= @due
        @status
      end

      def poke(offset, value)
        offset.zero? ? command(value) : @registers[offset] = value
      end

      def save_state(out)
        out.ints([*@registers, @status, @due, @result])
      end

      # A state from before the controller ran commands holds the four
      # registers alone.
      def load_state(input)
        values = input.ints
        @registers = values[0, 4]
        @status = values[4] || 0
        @due = values[5] || 0
        @result = values[6] || 0
      end

      private

      def command(value)
        return interrupt if (value & 0xf0) == 0xd0

        @registers[0] = value
        value < 0x80 ? step(value) : search(value)
      end

      # A restore ($0x), seek ($1x) or step ($2x to $7x), its track register
      # moved at once.
      def step(value)
        track = @registers[1]
        target = case value >> 4
                 when 0 then 0
                 when 1 then @registers[3]
                 else track + step_direction(value)
                 end
        @registers[1] = target.clamp(0, 255) if value < 0x20 || value.anybits?(0x10)
        start(STEP * [(target - track).abs, 1].max, @registers[1].zero? ? TRACK0 : 0)
      end

      # Step in ($4x) moves toward higher tracks, step out ($6x) toward
      # track 0, and step ($2x) the way the last one went.
      def step_direction(value)
        @direction = 1 if (value >> 5) == 2
        @direction = -1 if (value >> 5) == 3
        @direction || 1
      end

      # A sector or track command that finds no MFM sector.
      def search(value)
        value >= 0xf0 ? start(TURN, 0) : start(TURN * 5, NOT_FOUND)
      end

      def start(cycles, result)
        @status = BUSY | MOTOR_ON
        @due = @cpu.cycles + cycles
        @result = result
      end

      def finish
        @status = @result
      end

      def interrupt
        @status &= ~BUSY & 0xff
      end
    end
  end
end
