# frozen_string_literal: true

module Badline
  class Drive1581
    class WD1772
      # The four registers as the CPU reaches them, and a command written
      # to the command register.
      module Registers
        # Register +offset+, 0 to 3.
        def peek(offset)
          case offset
          when 0 then status
          when 1 then @track
          when 2 then @sector
          else read_data
          end
        end

        def poke(offset, value)
          case offset
          when 0 then write_command(value)
          when 1 then @track = value unless busy?
          when 2 then @sector = value unless busy?
          else write_data(value)
          end
        end

        # The status register, which clears INTRQ: after a type I command
        # bits 1, 2, 5 and 6 follow the index sensor, the track 0 sensor, the
        # spin-up and the write-protect line as they are now.
        def status
          @intrq = false
          value = @status | (@motor_on ? MOTOR_ON : 0) | (busy? ? BUSY : 0)
          return value | (@drq ? DATA_REQUEST : 0) unless @type1

          value |= PROTECTED if @mechanism.write_protected?
          value |= TRACK0 if @mechanism.track0?
          value | (@mechanism.index?(@now) ? INDEX : 0)
        end

        private

        def read_data
          @drq = false
          @data
        end

        def write_data(value)
          @drq = false
          @data = value
        end

        # A command while busy goes nowhere, but for a force interrupt.
        def write_command(value)
          @intrq = false
          return force_interrupt(value) if value & 0xf0 == 0xd0
          return if busy?

          @command = value
          @phase = STARTING
          @due = @now + START
        end

        def start_command
          if @command < 0x80 then start_type1
          elsif @command < 0xc0 then start_type2
          elsif @command & 0xf0 == 0xc0 then start_read_address
          else start_type3
          end
        end

        # Stops a command where it is, leaving its status but for BUSY, or
        # with none running switches the status to type I. I3 interrupts at
        # once and I2 at the next index pulse.
        def force_interrupt(value)
          @type1 = true unless busy?
          @drq = false
          idle
          @intrq = true if value.anybits?(0x08)
          return unless value.anybits?(0x04)

          @phase = INDEX_INTERRUPT
          @count = 1
          count_index
        end
      end
    end
  end
end
