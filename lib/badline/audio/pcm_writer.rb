# frozen_string_literal: true

module Badline
  module Audio
    # Streams mono signed 16-bit samples into a container, buffering them and
    # patching the header's length fields once the stream ends.
    class PCMWriter
      BUFFER = 4096

      attr_reader :rate, :samples

      def self.open(path, rate:)
        File.open(path, "wb") do |io|
          writer = new(io, rate:)
          yield writer
          writer.finish
        end
      end

      def initialize(io, rate:)
        @io = io
        @rate = rate
        @samples = 0
        @buffer = []
        @io.write(header)
      end

      def <<(sample)
        @buffer << sample
        flush if @buffer.length >= BUFFER
        self
      end

      def finish
        flush
        patch
      end

      private

      def flush
        return if @buffer.empty?

        @io.write(@buffer.pack(pack_format))
        @samples += @buffer.length
        @buffer.clear
      end

      def data_size = @samples * 2

      def write_at(offset, bytes)
        @io.seek(offset)
        @io.write(bytes)
      end
    end
  end
end
