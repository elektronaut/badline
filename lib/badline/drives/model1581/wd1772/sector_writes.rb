# frozen_string_literal: true

module Badline
  class Drive1581
    class WD1772
      # Write sector, once Sectors has found the ID: it asks for the first
      # byte 2 bytes after the ID's CRC and gives up at 22 with LOST_DATA,
      # then writes the data field where a format puts it, behind 12 x $00
      # and three $A1s, its mark deleted with a, a byte of 0 for each one
      # the CPU missed, and the CRC and a $FF after the last.
      module SectorWrites
        WRITE_REQUEST = 2
        WRITE_DEADLINE = 22

        private

        def write_sector(sector)
          @write_id = sector.id.mark
          @size = 128 << (sector.id.bytes[3] & 0x03)
          @gate_open = false
          @phase = WRITE_GATE
          @due = byte_end(@write_id + 6 + WRITE_REQUEST)
        end

        # Two bytes after the ID's CRC, DRQ asks for the first byte, and
        # twenty bytes on it has to be there.
        def write_gate
          unless @gate_open
            @gate_open = true
            @drq = true
            return @due += (WRITE_DEADLINE - WRITE_REQUEST) * BYTE
          end
          return lost if @drq

          @bytes = []
          @phase = WRITE_DATA
          @due = byte_end(@write_id + Track::DATA_OFFSET)
        end

        # The next byte goes under the head from the data register, a 0
        # where DRQ went unanswered, and DRQ asks for the one after it.
        # After the last come the CRC and a $FF.
        def byte_written
          return sector_written if @bytes.length == @size

          @status |= LOST_DATA if @drq && !@bytes.empty?
          @bytes << (@drq && !@bytes.empty? ? 0 : @data)
          @drq = @bytes.length < @size
          @due += @bytes.length == @size ? 3 * BYTE : BYTE
        end

        def sector_written
          sector = found
          if sector
            sector.data = Track::Field.new(@write_id + Track::DATA_OFFSET, @bytes, true,
                                           @command.anybits?(DELETED_MARK))
            @mechanism.write(@mechanism.track)
          end
          return finish if @command.nobits?(MULTIPLE)

          @sector = (@sector + 1) & 0xff
          begin_search
        end

        def lost
          @status |= LOST_DATA
          @drq = false
          finish
        end
      end
    end
  end
end
