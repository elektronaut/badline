# frozen_string_literal: true

module Badline
  module KernalTrap
    # One open channel on the virtual drive, holding a file, a block buffer
    # or the command channel's status message. It gives out one byte at a
    # time and flags the last one, so the bus can raise EOI with it. A
    # channel cut short by a read error never flags one, and holds the
    # error for the drive to report once its bytes run out.
    class Channel
      attr_accessor :pointer
      attr_reader :error

      def initialize(bytes = [], error: nil, writable: false)
        replace(bytes)
        @error = error
        @writable = writable
      end

      # A block buffer opened with "#". It takes the bytes written to it,
      # and hands out the whole block unless a B-R sets a shorter end.
      def self.buffer
        new(Array.new(Drive::BLOCK_SIZE, 0), writable: true)
      end

      # A file's bytes, up to the first block its chain can't read. The
      # drive reads a block ahead before sending the last byte of the one
      # before, so a bad block holds that byte back too, and a bad first
      # block or a missing file leaves nothing to send.
      def self.for_file(storage, name, type)
        data = storage.read_file(name, type:)
        return new([], error: [Drive::FILE_NOT_FOUND]) unless data

        failure = storage.respond_to?(:read_error) && storage.read_error(name, type:)
        return new(data) unless failure

        new(data[0, failure[:offset] - 1] || [], error: failure.values_at(:error, :track, :sector))
      end

      def replace(bytes, length = bytes.length)
        @bytes = bytes
        @length = length
        @pointer = 0
      end

      def writable? = @writable

      def exhausted?
        @pointer >= @length
      end

      # Each byte lands at the pointer, which wraps within the block.
      def write(bytes)
        bytes.each do |byte|
          @bytes[@pointer] = byte
          @pointer = (@pointer + 1) & 0xff
        end
      end

      def read
        return if exhausted?

        byte = @bytes[@pointer]
        @pointer += 1
        [byte, exhausted? && !@error]
      end
    end
  end
end
