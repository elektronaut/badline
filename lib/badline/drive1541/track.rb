# frozen_string_literal: true

module Badline
  class Drive1541
    # One ring of flux on the disk, as the GCR bytes the head reads from it,
    # most significant bit first, and the speed zone it was written in
    # (0-3). The bytes wrap around: the last one's bits run into the
    # first's. A track is as long as its bytes, which is what a .g64 image
    # stores for each half track.
    #
    # The disk turns at 300 rpm, so every track passes under the head in
    # the same 200 ms, and its bits pass at the rate they were written at.
    # Each bit is a cell of time, starting at the track's index angle with
    # the first byte's top bit, and a 1 bit is a flux transition at the
    # start of its cell. The cells are spread evenly over the turn, so a
    # track as long as a turn holds at its zone's rate
    # (Disk::TRACK_LENGTHS) passes at that rate, within the part of a byte
    # the length rounds off, and a longer or shorter one faster or slower.
    # A .g64 speed map gives each byte the zone it was written in, and the
    # cells of each byte are as wide as their zone's, scaled together to
    # fill the turn.
    #
    # Times are in TICKs, 1/65536 of a tick of the drive's 16 MHz crystal,
    # so the cells add up to a turn within a tick.
    class Track
      TICK = 1 << 16
      TURN = 200_000 * 16 * TICK

      # A bit cell at the zone's rate, in TICKs.
      def self.cell(zone) = 4 * (16 - zone) * TICK

      attr_reader :bytes, :zone, :speeds, :width, :widths

      # +speeds+ holds each byte's zone, where the track's rate changes
      # along it.
      def initialize(bytes, zone, speeds = nil)
        @bytes = bytes
        @zone = zone
        @speeds = speeds
        @widths = speeds && scaled_widths(speeds)
        @width = speeds ? @widths[0] : TURN / (bytes.length * 8)
      end

      def length = @bytes.length

      # Whether the whole track was written at the +zone+'s rate.
      def written_at?(zone) = @widths.nil? && @zone == zone

      # The bit cell under the head +time+ TICKs into the turn, as
      # [byte, mask, the time the cell ends].
      def cell_at(time)
        start = 0
        index = 0
        if @widths
          while index < length - 1 && time >= start + (@widths[index] * 8)
            start += @widths[index] * 8
            index += 1
          end
        else
          index = [time / (@width * 8), length - 1].min
          start = index * @width * 8
        end
        width = @widths ? @widths[index] : @width
        bit = [(time - start) / width, 7].min
        cell_end = index == length - 1 && bit == 7 ? TURN : start + ((bit + 1) * width)
        [index, 0x80 >> bit, cell_end]
      end

      # The track laid out again as one turn at the +zone+'s rate, each
      # flux transition in the cell under it.
      def relaid(zone)
        bits = Disk::TRACK_LENGTHS[zone] * 8
        cell = TURN / bits
        relaid = Array.new(bits / 8, 0)
        time = 0
        @bytes.each_with_index do |byte, index|
          width = @widths ? @widths[index] : @width
          8.times do |bit|
            if byte.anybits?(0x80 >> bit)
              cell_index = [time / cell, bits - 1].min
              relaid[cell_index >> 3] |= 0x80 >> (cell_index & 7)
            end
            time += width
          end
        end
        Track.new(relaid, zone)
      end

      private

      def scaled_widths(speeds)
        units = 0
        speeds.each { |zone| units += 16 - zone }
        speeds.map { |zone| TURN * (16 - zone) / (units * 8) }
      end
    end
  end
end
