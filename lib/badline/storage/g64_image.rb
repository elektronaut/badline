# frozen_string_literal: true

module Badline
  module Storage
    # A .g64 image: a 1541 disk's flux as raw GCR, track by track, for the
    # true drive to read the way it reads a real disk, copy protection and
    # all. It has no file system of its own, so only the true drive
    # (Drive1541::Disk.from_g64) can use it. A .g71 holds a 1571 disk the
    # same way, with "GCR-1571" for its signature and 168 half tracks,
    # the first side's 84 and then the second's.
    #
    # The header is the signature "GCR-1541", a version byte ($00), the
    # number of half tracks the tables cover (84, tracks 1 to 42.5) and
    # the longest track a block may hold, a little-endian word. Two tables
    # of little-endian longs follow, one entry per half track from track
    # 1: the file offset of each half track's block, 0 for one without
    # data, and its speed zone. A block is the track's length in bytes, a
    # word, and then its bytes.
    #
    # A speed entry of 0 to 3 is the zone the whole track was written in.
    # A larger one is the offset of a speed map, two bits a byte, four
    # track bytes to a map byte, the first byte's in the top two bits, for
    # a track whose zone changes along it. The drive passes each byte
    # under the head at its own zone's rate (Drive1541::Track).
    #
    # The drive writes a track at one zone, so a track written back takes
    # that zone as its speed entry. Writing it puts it in its own block,
    # where it fits, and otherwise appends a block to the file for it, as
    # for a half track that had no data. A track longer than the header's longest raises
    # it, so the header stays true of every block. A half track beyond
    # the tables stays on the disk alone. One opened with `read_only` is a
    # write-protected disk, and the host file is never written.
    #
    # Opening an image checks that its header and tables are whole, and
    # that every block and speed map lies past the tables and inside the
    # file, and raises FormatError where one doesn't.
    class G64Image
      class FormatError < StandardError; end

      SIGNATURE = "GCR-1541"
      SIGNATURE_1571 = "GCR-1571"
      HEADER_SIZE = 12
      HALF_TRACKS = 84
      MAX_TRACK_SIZE = 7928

      # A new image of +tracks+, {entry => [bytes, zone]} with entry 0 for
      # track 1 and 1 for track 1.5, laid out as VICE lays one out: every
      # block as long as the longest track.
      def self.create(path, tracks, half_tracks: HALF_TRACKS)
        max = [MAX_TRACK_SIZE, *tracks.values.map { |bytes, _| bytes.length }].max
        offsets = Array.new(half_tracks, 0)
        zones = Array.new(half_tracks, 0)
        blocks = +"".b
        position = HEADER_SIZE + (half_tracks * 8)
        tracks.keys.sort.each do |entry|
          bytes, zones[entry] = tracks[entry]
          offsets[entry] = position + blocks.bytesize
          blocks << block(bytes, max)
        end
        header = SIGNATURE.b + [0, half_tracks, max].pack("CCv")
        File.binwrite(path, header + offsets.pack("V*") + zones.pack("V*") + blocks)
        new(path)
      end

      def self.block(bytes, size)
        [bytes.length].pack("v") + bytes.pack("C*").ljust(size, "\x00".b)
      end

      attr_reader :half_tracks, :max_track_size

      def initialize(path, read_only: false)
        @path = path
        @read_only = read_only
        @data = File.binread(path)
        parse
      end

      # Whether the image was opened write-protected.
      def read_only? = @read_only

      # Whether the host file takes writes.
      def writable? = !read_only? && File.writable?(@path)

      # The track at table entry +entry+ (0 for track 1) as [bytes, zone],
      # or nil where it has no data. A speed-mapped track's zone is the one
      # most of its bytes were written in.
      def track(entry)
        offset = @offsets[entry].to_i
        return if offset.zero?

        length = block_length(offset)
        return if length.zero?

        speeds = mapped_speeds(entry, length)
        [@data.byteslice(offset + 2, length).bytes, speeds ? majority(speeds) : @speeds[entry]]
      end

      # Each byte's zone of the track at table entry +entry+, where its
      # speed map changes along it, and nil otherwise.
      def speeds(entry)
        offset = @offsets[entry].to_i
        return if offset.zero?

        speeds = mapped_speeds(entry, block_length(offset))
        speeds unless speeds.nil? || speeds.uniq.one?
      end

      # Stores tracks the drive wrote, {entry => [bytes, zone]}, in one
      # write to the host file. Each takes its zone as its speed entry.
      def store_tracks(tracks)
        raise WriteError, WriteError::WRITE_PROTECT_ON unless writable?

        data = @data.dup
        tracks.each do |entry, (bytes, zone)|
          next unless entry < @half_tracks

          store_track(data, entry, bytes, zone)
        end
        File.binwrite(@path, data)
        @data = data
        parse
      rescue SystemCallError
        parse
        raise WriteError, WriteError::WRITE_PROTECT_ON
      end

      private

      def parse
        unless @data.start_with?(SIGNATURE) || @data.start_with?(SIGNATURE_1571)
          raise FormatError, "Missing G64 signature"
        end
        raise FormatError, "G64 header is cut short" if @data.bytesize < HEADER_SIZE

        version, @half_tracks, @max_track_size = @data.byteslice(8, 4).unpack("CCv")
        raise FormatError, "Unsupported G64 version #{version}" unless version.zero?

        tables = @data.byteslice(HEADER_SIZE, @half_tracks * 8).to_s
        raise FormatError, "G64 track tables are cut short" if tables.bytesize < @half_tracks * 8

        @offsets = tables.byteslice(0, @half_tracks * 4).unpack("V*")
        @speeds = tables.byteslice(@half_tracks * 4, @half_tracks * 4).unpack("V*")
        @half_tracks.times { |entry| check_block(entry) }
      end

      def tables_end = HEADER_SIZE + (@half_tracks * 8)

      def block_length(offset) = @data.byteslice(offset, 2).unpack1("v")

      def check_block(entry)
        offset = @offsets[entry]
        return if offset.zero?

        problem = misplaced(offset, 2) || misplaced(offset, 2 + block_length(offset))
        raise FormatError, "G64 track entry #{entry} #{problem}" if problem

        check_speed_map(entry, block_length(offset))
      end

      def check_speed_map(entry, length)
        speed = @speeds[entry]
        return if speed <= 3

        problem = misplaced(speed, (length + 3) / 4)
        raise FormatError, "G64 speed map of track entry #{entry} #{problem}" if problem
      end

      # What's wrong with +size+ bytes at +offset+, or nil where they lie
      # past the tables and inside the file.
      def misplaced(offset, size)
        if offset < tables_end then "points into the header or its tables"
        elsif offset + size > @data.bytesize then "runs past the end of the image"
        end
      end

      # Each byte's zone from the track's speed map, or nil where its speed
      # entry is a zone.
      def mapped_speeds(entry, length)
        speed = @speeds[entry]
        return if speed <= 3

        map = @data.byteslice(speed, (length + 3) / 4).to_s.bytes
        Array.new(length) { |index| (map[index >> 2] >> (6 - ((index & 3) * 2))) & 3 }
      end

      # The zone most of the bytes were written in.
      def majority(speeds)
        counts = [0, 0, 0, 0]
        speeds.each { |zone| counts[zone] += 1 }
        counts.index(counts.max)
      end

      def store_track(data, entry, bytes, zone)
        offset = @offsets[entry]
        if offset.zero? || bytes.length > capacity(offset)
          offset = data.bytesize
          grow(data, bytes.length)
          data << self.class.block(bytes, @max_track_size)
        else
          data[offset, bytes.length + 2] = [bytes.length].pack("v") + bytes.pack("C*")
        end
        set_entry(data, entry, offset, zone)
      end

      # The most bytes the block at +offset+ holds without running into
      # the next block or speed map, or off the end of the file.
      def capacity(offset)
        ends = (@offsets + @speeds.select { |speed| speed > 3 }).select { |start| start > offset }
        ends.push(@data.bytesize).min - offset - 2
      end

      def grow(data, length)
        return if length <= @max_track_size

        @max_track_size = length
        data[10, 2] = [length].pack("v")
      end

      def set_entry(data, entry, offset, zone)
        @offsets[entry] = offset
        @speeds[entry] = zone
        data[HEADER_SIZE + (entry * 4), 4] = [offset].pack("V")
        data[HEADER_SIZE + ((@half_tracks + entry) * 4), 4] = [zone].pack("V")
      end
    end
  end
end
