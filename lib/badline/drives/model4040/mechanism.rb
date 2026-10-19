# frozen_string_literal: true

module Badline
  module Drives
    class Model4040
      # The unit's two SA390 drives as the 6504 sees them through the VIA
      # and the 6530 (schematic 320806, sheets 2 and 3).
      #
      # VIA port B runs the drives: PB5 drive 0's motor and PB4 drive 1's,
      # each on while low, PB2-3 drive 0's stepper and PB0-1 drive 1's. The
      # 6530's port B picks the drive on PB0 and the zone on PB1-2, and
      # reads write protect on PB3, high while the disk can't be written,
      # and SYNC on PB6, low while ten one bits sit in the shift register.
      # Its port A holds the byte to write.
      #
      # Each stepper's two bits count in binary: one up moves the head half
      # a track in, one down half a track out, and the controller steps
      # once an interrupt, twice a track ($FF82), bumping the head against
      # track 1 with 116 steps out.
      #
      # A turning disk passes one byte cell under the head every ten bit
      # cells, at 16 MHz divided by 16 less the track's zone and then by 4,
      # and the byte cells come round 300 times a minute (Disk). Each data
      # cell ends in byte ready, which latches the byte into VIA port A
      # through CA1; the controller has no SO pin and polls the VIA's
      # interrupt flags for it. A sync cell holds SYNC low instead. While
      # the VIA's CB2 is low the drive writes: each cell takes the 6530's
      # port A, or a sync while CA2 is high, and still ends in byte ready.
      # The format code holds CA2 high in pulse mode, which reading port A
      # pulls low for a cycle.
      class Mechanism
        WRITE_PROTECT = 0x08
        SYNC_LINE = 0x40

        # The half tracks a head can reach: track 1 to 35.
        HALF_TRACKS = 70

        attr_reader :data_in, :half_tracks
        attr_accessor :via, :rriot

        def initialize
          @via = nil
          @rriot = nil
          @disks = [nil, nil]
          @half_tracks = [0, 0]
          @phases = [0, 0]
          @positions = [0, 0]
          @clocks = [0, 0]
          @motors = [false, false]
          @data_in = 0xff
          @syncs = [false, false]
          @ca1_low = false
        end

        # The Disk in +drive+, 0 or 1, or nil.
        def disk(drive = 0) = @disks[drive]

        def insert(disk, drive = 0)
          @disks[drive]&.flush
          @disks[drive] = disk
        end

        def flush
          @disks.each { |disk| disk&.flush }
        end

        def motor_on?(drive = 0) = @motors[drive]

        # The track under +drive+'s head, 1 to 35.
        def track(drive = 0) = (@half_tracks[drive] >> 1) + 1

        def cycle!
          if @ca1_low
            @ca1_low = false
            @via.ca1 = true
          end
          drives = @via.port_b_output
          turn(0, drives.nobits?(0x20), (drives >> 2) & 0x03)
          turn(1, drives.nobits?(0x10), drives & 0x03)
        end

        # Whether a cycle would change nothing: both motors off and no byte
        # ready under way.
        def quiet? = !@motors[0] && !@motors[1] && !@ca1_low

        # What the drives hold, for comparing them at two points.
        def idle_state = [*@half_tracks, *@phases, *@motors, *@syncs, @data_in]

        # The 6530's port B inputs.
        def status_lines
          drive = selected_drive
          lines = 0xff
          lines &= ~WRITE_PROTECT unless @disks[drive]&.write_protected?
          @syncs[drive] ? lines & ~SYNC_LINE : lines
        end

        private

        def selected_drive = @rriot.port_b_output & 0x01

        def turn(drive, motor, phase)
          step(drive, phase) if phase != @phases[drive]
          motor_off(drive) if @motors[drive] && !motor
          @motors[drive] = motor
          return @syncs[drive] = false unless motor && @disks[drive]

          clock = @clocks[drive] + 2
          byte = 5 * (16 - Disk.zone_of(track(drive)))
          if clock >= byte
            clock -= byte
            pass_cell(drive)
          end
          @clocks[drive] = clock
        end

        def step(drive, phase)
          change = (phase - @phases[drive]) & 0x03
          @phases[drive] = phase
          half_track = @half_tracks[drive]
          if change == 1
            half_track += 1
          elsif change == 3
            half_track -= 1
          end
          @half_tracks[drive] = half_track.clamp(0, HALF_TRACKS - 1)
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

        def writing? = !@via.cb2_output

        def read_cell(drive, cells, position)
          cell = cells[position]
          @syncs[drive] = cell == Disk::SYNC
          byte_ready(cell) unless cell == Disk::SYNC
        end

        def write_cell(drive, disk, number, cells, position)
          cells[position] = @via.ca2_output ? Disk::SYNC : @rriot.port_a_output
          disk.written(number)
          @syncs[drive] = false
          byte_ready(@data_in)
        end

        def byte_ready(byte)
          @data_in = byte
          @via.ca1 = false
          @ca1_low = true
        end
      end

      # VIA port A reads the byte the last cell latched. Port B drives the
      # drives only.
      class ReadLines
        def initialize(mechanism)
          @mechanism = mechanism
        end

        def read_a(_lines) = @mechanism.data_in

        def read_b(_lines) = 0xff
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
