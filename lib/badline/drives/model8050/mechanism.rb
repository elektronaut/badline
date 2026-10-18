# frozen_string_literal: true

module Badline
  module Drives
    class Model8050
      # The unit's two drives as the floppy controller sees them through
      # the VIA and the 6530 (schematic 8050001, sheets 2 and 3).
      #
      # VIA port B runs the drives: PB5 drive 0's motor and PB4 drive 1's,
      # each on while low, PB2-3 drive 0's stepper phases and PB0-1 drive
      # 1's, and PB7 reads SYNC, low while ten one bits sit in the shift
      # register. The 6530's port B picks the drive on PB0, the zone on
      # PB1-2 and the side on PB4, low for the second, and reads write
      # protect on PB3, high while the disk can't be written, and the sides
      # on PB6, low for two, which jumper E3 grounds on the 8250. Its port
      # A holds the byte to write.
      #
      # Each phase change moves the head a track: the controller steps
      # through the Gray code 00, 10, 11, 01 outward and back the other way
      # inward ($FF9C), and bumps the head against track 1 with 92 steps
      # out.
      #
      # A turning disk passes one byte cell under the head every ten bit
      # cells, at 6 MHz divided by 16 less the track's zone, and the byte
      # cells come round 300 times a minute (Disk). Each data cell ends in
      # byte ready, which latches the GCR ROM's byte into VIA port A through
      # CA1 and pulses the controller's SO pin; a sync cell holds SYNC low
      # for the cell after it instead. While the VIA's CB2 is low the drive
      # writes: each cell takes the 6530's port A, or a sync while CA2 is
      # high, and still ends in byte ready.
      #
      # A disk going in or out passes the write-protect sensor, which the
      # controller watches for a disk change: it reads high for a while.
      class Mechanism
        WRITE_PROTECT = 0x08
        ONE_SIDE = 0x40

        # The cycles the write-protect sensor reads high as a disk goes in
        # or out, ten of the controller's 5 ms interrupts.
        CHANGE_CYCLES = 50_000

        attr_reader :sides, :data_in, :cylinders, :so_pending
        attr_accessor :via, :rriot

        def initialize(sides:)
          @sides = sides
          @via = nil
          @rriot = nil
          @disks = [nil, nil]
          @cylinders = [0, 0]
          @phases = [0, 0]
          @positions = [0, 0]
          @clocks = [0, 0]
          @changing = [0, 0]
          @motors = [false, false]
          @so_pending = false
          @data_in = 0xff
          @syncs = [false, false]
          @ca1_low = false
        end

        # The Disk in +drive+, 0 or 1, or nil.
        def disk(drive = 0) = @disks[drive]

        def insert(disk, drive = 0)
          @disks[drive]&.flush
          @disks[drive] = disk
          @changing[drive] = CHANGE_CYCLES
        end

        def flush
          @disks.each { |disk| disk&.flush }
        end

        def motor_on?(drive = 0) = @motors[drive]

        # The track under +drive+'s head on the side the 6530 picks.
        def track(drive = 0)
          side = drive == selected_drive ? selected_side : 0
          @cylinders[drive] + 1 + (side * Storage::D80Image::SIDE_TRACKS)
        end

        def cycle!
          if @ca1_low
            @ca1_low = false
            @via.ca1 = true
          end
          drives = @via.port_b_output
          turn(0, drives.nobits?(0x20), (drives >> 2) & 0x03)
          turn(1, drives.nobits?(0x10), drives & 0x03)
        end

        # Whether a cycle would change nothing: both motors off, no disk
        # going in or out, and no byte ready under way.
        def quiet?
          !@motors[0] && !@motors[1] && @changing[0].zero? && @changing[1].zero? && !@ca1_low && !@so_pending
        end

        # What the drives hold, for comparing them at two points.
        def idle_state = [*@cylinders, *@phases, *@motors, *@syncs, @data_in]

        # Whether byte ready pulses the controller's SO pin this cycle,
        # which takes the pulse.
        def take_so
          so = @so_pending
          @so_pending = false
          so
        end

        # Whether ten one bits sit in the shift register, off the selected
        # drive's head.
        def sync? = @syncs[selected_drive]

        # The 6530's port B inputs.
        def status_lines
          lines = 0xff
          lines &= ~WRITE_PROTECT unless write_protected?(selected_drive)
          @sides == 2 ? lines & ~ONE_SIDE : lines
        end

        private

        def selected_drive = @rriot.port_b_output & 0x01

        def selected_side = @sides == 2 && @rriot.port_b_output.nobits?(0x10) ? 1 : 0

        def write_protected?(drive)
          return true if @changing[drive].positive?

          disk = @disks[drive]
          disk ? disk.write_protected? : false
        end

        def turn(drive, motor, phase)
          @changing[drive] -= 1 if @changing[drive].positive?
          step(drive, phase) if phase != @phases[drive]
          motor_off(drive) if @motors[drive] && !motor
          @motors[drive] = motor
          return @syncs[drive] = false unless motor && @disks[drive]

          clock = @clocks[drive] + 6
          byte = 10 * (16 - Disk.zone_of(track(drive)))
          if clock >= byte
            clock -= byte
            pass_cell(drive)
          end
          @clocks[drive] = clock
        end

        # Gray code index of a phase pair: 00, 10, 11, 01.
        def phase_index(phase) = [0, 3, 1, 2][phase]

        def step(drive, phase)
          change = (phase_index(phase) - phase_index(@phases[drive])) & 0x03
          @phases[drive] = phase
          cylinder = @cylinders[drive]
          if change == 1
            cylinder -= 1
          elsif change == 3
            cylinder += 1
          end
          @cylinders[drive] = cylinder.clamp(0, Storage::D80Image::SIDE_TRACKS - 1)
        end

        def motor_off(drive)
          @disks[drive]&.flush
        end

        # A cell has passed under +drive+'s head.
        def pass_cell(drive)
          disk = @disks[drive]
          number = track(drive)
          cells = disk.track(number)
          return unless cells

          position = @positions[drive] % cells.length
          @positions[drive] = position + 1
          return unless drive == selected_drive

          writing? ? write_cell(drive, disk, number, cells, position) : read_cell(drive, cells, position)
        end

        def writing? = (@via.pcr & 0xe0) == 0xc0

        def read_cell(drive, cells, position)
          cell = cells[position]
          @syncs[drive] = cell == Disk::SYNC
          byte_ready(cell) unless cell == Disk::SYNC
        end

        def write_cell(drive, disk, number, cells, position)
          cells[position] = @via.pcr.allbits?(0x0e) ? Disk::SYNC : @rriot.port_a_output
          disk.written(number)
          @syncs[drive] = false
          byte_ready(@data_in)
        end

        def byte_ready(byte)
          @data_in = byte
          @via.ca1 = false
          @ca1_low = true
          @so_pending = true
        end
      end

      # VIA port A reads the decoded byte, and PB7 SYNC, low while the
      # shift register holds a sync.
      class ReadLines
        def initialize(mechanism)
          @mechanism = mechanism
        end

        def read_a(_lines) = @mechanism.data_in

        def read_b(_lines) = @mechanism.sync? ? 0x7f : 0xff
      end

      # The 6530's port B inputs from the drives.
      class StatusLines
        def initialize(mechanism)
          @mechanism = mechanism
        end

        def read_a(_lines) = 0xff

        def read_b(_lines) = @mechanism.status_lines
      end
    end
  end
end
