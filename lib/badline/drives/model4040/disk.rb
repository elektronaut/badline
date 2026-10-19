# frozen_string_literal: true

module Badline
  module Drives
    class Model4040
      # A .d64 image as the 4040's controller finds it on the disk, each
      # track a ring of byte cells as on the 8050 (Model8050::Disk), laid
      # out as DOS 2.1's format writes it, sector after sector:
      #
      #   4 sync, $08, checksum, sector, track, ID 2, ID 1,
      #   9 x $00, 4 sync, $07, 256 data bytes, checksum, then $00
      #
      # nine cells being the header gap the interface processor gives the
      # controller ($049D, from DOS 2.1's SECTRK table), past which a write
      # puts its syncs. The disk's ID is the BAM's, at 18/0 $A2. A turn
      # passes 80,000 / (16 - zone) cells, the 16 MHz bit clock's.
      class Disk < Model8050::Disk
        # How many tracks a disk holds: 35.
        def side_tracks = 35

        def sides = 1

        # The cells a track of the zone holds in one turn at 300 rpm: the
        # 200,000 µs of a turn over 2.5 µs times 16 less the zone a byte.
        def self.cells_in(zone) = 80_000 / (16 - zone)

        # The zone a track is recorded in, 3 outermost to 0 innermost.
        def self.zone_of(track) = Storage::D64Image.zone(track)

        private

        def build(number)
          id1, id2 = disk_id
          cells = []
          sectors = @image.sectors_in(number)
          sectors.times do |sector|
            data = @image.read_block(number, sector)
            cells.push(SYNC, SYNC, SYNC, SYNC, 0x08, number ^ sector ^ id1 ^ id2, sector, number, id2, id1)
            cells.concat(Array.new(9, 0x00))
            cells.push(SYNC, SYNC, SYNC, SYNC, 0x07)
            cells.concat(data)
            cells << checksum(data)
          end
          pad(cells, sectors, self.class.cells_in(self.class.zone_of(number)))
        end

        def disk_id
          bam = @image.read_block(18, 0)
          [bam[0xa2], bam[0xa3]]
        end
      end
    end
  end
end
