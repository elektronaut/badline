# frozen_string_literal: true

module Badline
  class Drive1541
    # Reads a track's blocks back out of its GCR, as the DOS finds them:
    # each SYNC mark is ten or more 1 bits, and the block after it starts
    # at the first 0 bit. Writes land wherever the head was, so a block
    # can start at any bit of the stored bytes, and the reader works on
    # the bits.
    #
    # A header block starts with $08, and the next block after a header is
    # that sector's data block, whatever it holds.
    module SectorReader
      HEADER_BITS = 10 * 8
      DATA_BITS = 325 * 8
      SYNC = /1{10,}/

      # A sector as read: its decoded header, [ID, checksum, sector, track,
      # the second ID byte, the first, ...], and its decoded data block,
      # [ID, 256 data bytes, checksum, ...], nil when there isn't one that
      # decodes.
      Sector = Struct.new(:header, :data)

      module_function

      # The sectors found on the track's bytes, by sector number. Headers
      # for another track are left out.
      def read(bytes, track)
        ring = ring(bytes)
        return {} unless ring

        sectors = {}
        each_block(ring) do |header, data|
          next unless header[3] == track

          sectors[header[2]] ||= Sector.new(header, data)
        end
        sectors
      end

      # The track's bits, starting at a 0 bit so no SYNC mark straddles the
      # start, twice over so a block can run on past the end. Nil for a
      # track without a 0 bit.
      def ring(bytes)
        bits = bytes.pack("C*").unpack1("B*")
        zero = bits.index("0")
        return unless zero

        bits = bits[zero..] + bits[0, zero]
        [bits * 2, bits.length]
      end

      # Yields each header whose SYNC mark starts in the first turn, with
      # the data block after it.
      def each_block(ring)
        bits, length = ring
        pos = 0
        while (sync = SYNC.match(bits, pos)) && sync.begin(0) < length
          pos = sync.end(0)
          header = decode(bits, pos, HEADER_BITS)
          next unless header && header[0] == Disk::HEADER_ID

          data_sync = SYNC.match(bits, pos + HEADER_BITS)
          yield header, data_sync && decode(bits, data_sync.end(0), DATA_BITS)
        end
      end

      def decode(bits, pos, count)
        slice = bits[pos, count]
        return unless slice.length == count

        GCR.decode([slice].pack("B*").bytes)
      end
    end
  end
end
