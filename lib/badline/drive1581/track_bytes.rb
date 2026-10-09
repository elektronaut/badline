# frozen_string_literal: true

module Badline
  class Drive1581
    class Track
      # A Track as the bytes going round under the head, for the WD1772's
      # read track: its fields with their gaps and sync marks.
      module Bytes
        # The track's LENGTH bytes from the index: $4E gaps, and before each
        # field 12 x $00 and three $A1 sync marks, its mark, its bytes and
        # its CRC, spoiled where the field's CRC doesn't read back.
        def raw
          bytes = Array.new(LENGTH, GAP)
          @sectors.each do |sector|
            lay(bytes, sector.id, ID_MARK)
            data = sector.data
            lay(bytes, data, data.deleted ? DELETED_MARK : DATA_MARK) if data
          end
          bytes
        end

        private

        def lay(bytes, field, mark)
          start = field.mark - 15
          crc = Track.field_crc(mark, field.bytes)
          crc[1] ^= 0xff unless field.good
          [*Array.new(12, 0), SYNC, SYNC, SYNC, mark, *field.bytes, *crc].each_with_index do |byte, i|
            bytes[start + i] = byte if start + i < LENGTH
          end
        end
      end

      # Finding the fields in the bytes a write track laid down.
      module Parse
        # Every sector in +bytes+, a turn as a write track laid it down,
        # where +syncs+ marks the $A1s written as sync marks: an ID mark
        # behind three of them, its four bytes and CRC, and the data field
        # that follows it within DATA_MARK_WINDOW bytes, its length from
        # the ID's size code.
        def parse(bytes, syncs)
          sectors = []
          position = 0
          while (mark = find_mark(bytes, syncs, position...bytes.length, ID_MARK..ID_MARK))
            id = read_field(bytes, mark, 4)
            position = mark + 7
            data_mark = find_mark(bytes, syncs, position...(position + DATA_MARK_WINDOW), DELETED_MARK..DATA_MARK)
            sectors << Sector.new(id, data_mark && read_field(bytes, data_mark, 128 << (id.bytes[3] & 3)))
          end
          new(sectors)
        end

        private

        # The first place in +range+ that holds one of +marks+ behind three
        # sync marks.
        def find_mark(bytes, syncs, range, marks)
          ([range.first, 3].max...[range.end, bytes.length].min).find do |at|
            marks.cover?(bytes[at]) && syncs[at - 1] && syncs[at - 2] && syncs[at - 3]
          end
        end

        def read_field(bytes, mark, length)
          field = bytes[mark + 1, length] || []
          field += Array.new(length - field.length, 0)
          crc = bytes[mark + 1 + length, 2] || []
          Field.new(mark, field, crc == Track.field_crc(bytes[mark], field), bytes[mark] < 0xfa)
        end
      end

      include Bytes
      extend Parse
    end
  end
end
