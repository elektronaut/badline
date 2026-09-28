# frozen_string_literal: true

module Badline
  class Drive1541
    # One ring of flux on the disk, as the GCR bytes the head reads from it,
    # most significant bit first, and the speed zone it was written in
    # (0-3). The bytes wrap around: the last one's bits run into the
    # first's. A track is as long as its bytes, which is what a .g64 image
    # stores for each half track.
    class Track
      attr_reader :bytes, :zone

      def initialize(bytes, zone)
        @bytes = bytes
        @zone = zone
      end

      def length = @bytes.length
    end
  end
end
