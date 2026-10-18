# frozen_string_literal: true

module Badline
  module Drives
    class Model8050
      # A .d80 or .d82 image as the floppy controller finds it on the disk:
      # each track a ring of byte cells, each cell ten bit cells the GCR ROM
      # turns into a data byte (Track::SYNC for a run of ones), so the
      # mechanism needs no GCR. A track is laid out as the DOS's format code
      # writes it ($C000-$C363 of DOS 2.7, run on the controller), sector
      # after sector:
      #
      #   4 sync, $08, checksum, sector, track, ID 2, ID 1, $0F,
      #   19 x $0F, 5 sync, $07, 256 data bytes, checksum, then $00
      #
      # the header checksum the EOR of the track, sector and IDs, and the
      # data block's that of its bytes. The $00 gaps share out what the
      # track has left over.
      #
      # Tracks come off the image as the head first reaches them. What the
      # head writes goes back to the image when the motor stops (flush):
      # every data block found on a written track whose header and checksum
      # read cleanly.
      class Disk
        SYNC = 0x100

        attr_reader :image

        def initialize(image)
          @image = image
          @tracks = {}
          @written = {}
        end

        def write_protected? = @image.read_only?

        # The image's host file.
        def path = @image.path

        # How many tracks a side holds: 77.
        def side_tracks = Storage::D80Image::SIDE_TRACKS

        def sides = @image.is_a?(Storage::D82Image) ? 2 : 1

        # The cells of +track+, 1 to 77 on the first side and 78 to 154 on
        # the second, or nil past the disk's last.
        def track(number)
          return nil unless number.between?(1, side_tracks * sides)

          @tracks[number] ||= build(number)
        end

        # The cells a track of the zone holds in one turn at 300 rpm: the
        # 200,000 cycles of a turn over the zone's ten bit cells a byte at
        # 6 MHz / (16 - zone).
        def self.cells_in(zone) = 120_000 / (16 - zone)

        # The zone a track is recorded in, 3 outermost to 0 innermost.
        def self.zone_of(track)
          cylinder = ((track - 1) % Storage::D80Image::SIDE_TRACKS) + 1
          3 - Storage::D80Image::ZONE_LAST_TRACKS.count { |last| cylinder > last }
        end

        # The head wrote to +track+.
        def written(number)
          @written[number] = true
        end

        # Stores the blocks the head wrote in the image.
        def flush
          return if @written.empty?

          blocks = []
          @written.each_key { |number| blocks.concat(read_blocks(@tracks[number])) }
          @written.clear
          @image.store_blocks(blocks) unless blocks.empty?
        end

        private

        def build(number)
          id1, id2 = disk_id
          cells = []
          sectors = @image.sectors_in(number)
          sectors.times do |sector|
            data = @image.read_block(number, sector)
            cells.push(SYNC, SYNC, SYNC, SYNC, 0x08, number ^ sector ^ id1 ^ id2, sector, number, id2, id1)
            cells.concat(Array.new(20, 0x0f))
            cells.push(SYNC, SYNC, SYNC, SYNC, SYNC, 0x07)
            cells.concat(data)
            cells << checksum(data)
          end
          pad(cells, sectors, self.class.cells_in(self.class.zone_of(number)))
        end

        # Shares the $00 gap out after each sector.
        def pad(cells, sectors, length)
          sector_length = cells.length / sectors
          gap = (length - cells.length) / sectors
          padded = []
          sectors.times do |sector|
            padded.concat(cells[sector * sector_length, sector_length])
            padded.concat(Array.new(sector == sectors - 1 ? length - padded.length : gap, 0x00))
          end
          padded
        end

        def checksum(bytes)
          sum = 0
          bytes.each { |byte| sum ^= byte }
          sum
        end

        # The ID the header block holds at $18.
        def disk_id
          header = @image.read_block(*@image.header_block)
          [header[0x18], header[0x19]]
        end

        # Every block whose header and data read cleanly off +cells+, as
        # [track, sector, data, nil].
        def read_blocks(cells)
          blocks = []
          index = 0
          length = cells.length
          while (index = next_block(cells, index, 0x08))
            header = Array.new(5) { |offset| cells[(index + offset) % length] }
            index = next_block(cells, index, 0x07)
            break unless index

            block = data_block(cells, index, header)
            blocks << block if block
            break if index + 260 >= length
          end
          blocks
        end

        # The cell after the next sync run followed by +mark+, from
        # +index+, or nil.
        def next_block(cells, index, mark)
          length = cells.length
          while index < length
            return index + 2 if cells[index] == SYNC && cells[(index + 1) % length] == mark

            index += 1
          end
          nil
        end

        def data_block(cells, index, header)
          checksum, sector, track, id2, id1 = header
          return nil unless checksum == (track ^ sector ^ id1 ^ id2)

          length = cells.length
          data = Array.new(256) { |offset| cells[(index + offset) % length] }
          return nil if data.include?(SYNC) || checksum(data) != cells[(index + 256) % length]

          [track, sector, data, nil]
        end
      end
    end
  end
end
