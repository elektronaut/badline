# frozen_string_literal: true

module Badline
  class Drive1581
    class WD1772
      # The type III commands that take a whole turn, from one index pulse
      # to the next:
      #
      #   11100hE00  read track   every byte under the head (Track#raw)
      #   11110hEP0  write track  every byte the CPU sends, for a format
      #
      # Write track asks for its first byte at once and starts at the index
      # pulse, giving up with LOST_DATA if the byte hasn't come three bytes
      # later. $F5 writes a sync mark, an $A1, and the first of a run starts
      # the CRC over; $F6 writes $C2; $F7 writes the CRC's two bytes. At
      # the next index pulse the track under the head becomes the fields
      # found in what went down (Track.parse).
      module Tracks
        LATE = 3

        private

        def start_type3
          @type1 = false
          @status = 0
          @drq = false
          @mode = @command.anybits?(0x10) ? WRITE : READ
          resume_track unless spinning_up?(TRACK_INDEX)
        end

        def resume_track
          if @mode == WRITE
            if @mechanism.write_protected?
              @status |= PROTECTED
              return finish
            end
            @drq = true
          end
          @phase = @mode == WRITE ? WRITE_TRACK_START : TRACK_INDEX
          return wait_index(@phase) if @command.nobits?(SETTLE_DELAY)

          @due = @now + SETTLE
          @settling = true
        end

        def wait_index(phase)
          @settling = false
          @phase = phase
          @due = next_index
        end

        def track_index
          return wait_index(TRACK_INDEX) if @settling

          @bytes = (@mechanism.track || Track.new([])).raw
          @index = 0
          @phase = READ_TRACK
          @due = @now + BYTE
        end

        def track_byte_read
          @status |= LOST_DATA if @drq
          @data = @bytes[@index]
          @drq = true
          @index += 1
          @index == Track::LENGTH ? finish : @due += BYTE
        end

        def write_track_start
          return wait_index(WRITE_TRACK_START) if @settling

          @bytes = []
          @syncs = []
          @crc = 0xffff
          @phase = WRITE_TRACK
          return track_byte_written unless @drq

          @late = true
          @due = @now + (LATE * BYTE)
        end

        # The next byte from the data register goes under the head, a 0
        # where DRQ went unanswered.
        def track_byte_written
          return lost if @late && @drq
          return track_written if @bytes.length >= Track::LENGTH

          @late = false
          value = @drq ? 0 : @data
          @status |= LOST_DATA if @drq
          @drq = true
          before = @bytes.length
          lay_byte(value)
          @due = @now + ((@bytes.length - before) * BYTE)
        end

        def lay_byte(value)
          case value
          when 0xf5
            @crc = 0xffff unless @syncs.last
            push_byte(Track::SYNC, true)
          when 0xf6 then push_byte(0xc2, false)
          when 0xf7
            crc = @crc
            push_byte(crc >> 8, false)
            push_byte(crc & 0xff, false)
          else push_byte(value, false)
          end
        end

        def push_byte(value, sync)
          @bytes << value
          @syncs << sync
          @crc = Track.crc([value], @crc)
        end

        def track_written
          @drq = false
          @mechanism.write(Track.parse(@bytes.first(Track::LENGTH), @syncs))
          finish
        end
      end
    end
  end
end
