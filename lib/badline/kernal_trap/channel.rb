# frozen_string_literal: true

module Badline
  module KernalTrap
    # One open channel on the virtual drive, holding a file, a block buffer
    # or the command channel's status message. It gives out one byte at a
    # time and flags the last one, so the bus can raise EOI with it. A
    # channel cut short by a read error never flags one, and holds the
    # error for the drive to report once its bytes run out.
    class Channel
      attr_accessor :buffer
      attr_reader :error, :pointer
      attr_writer :lead

      def initialize(bytes = [], error: nil, writable: false, base: 0)
        @base = base
        replace(bytes)
        @error = error
        @writable = writable
      end

      # A block buffer opened with "#", which reads and writes one of the
      # drive's buffers in its RAM, so M-R and M-W reach the same bytes. It
      # hands out the whole block unless a B-R sets a shorter end. The DOS
      # opens it with the pointer at 1 and the buffer's number as the byte
      # to send, so the first read answers with the number and the next
      # one moves on to the third byte.
      def self.buffer(memory, number)
        new(memory.ram, writable: true, base: Drive::Memory.buffer_address(number)).tap do |channel|
          channel.buffer = number
          channel.rewind(Drive::BLOCK_SIZE)
          channel.pointer = 1
          channel.lead = number
        end
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

      # The file an open names. The drive keeps the first block of the file
      # a LOAD (secondary address 0) opens at $7E and $026F of its memory,
      # and a LOAD of a name starting with "*" reopens that file rather than
      # the first one on the disk. Loaders write the block there with M-W
      # to load a file the directory doesn't list.
      def self.for_name(storage, memory, secondary, name, type)
        file = Storage.parse_name(name).first
        return for_file(storage, file, type) unless secondary.zero? && storage.respond_to?(:first_block)

        last = memory.last_program if name.start_with?("*")
        return at_block(storage, *last) if last

        block = storage.first_block(file, type:)
        memory.last_program = block if block
        for_file(storage, file, type)
      end

      # The file whose chain starts at the block.
      def self.at_block(storage, track, sector)
        data = storage.read_file_at(track, sector)
        data ? new(data) : new([], error: [Drive::ILLEGAL_TRACK_OR_SECTOR, track, sector])
      end

      def replace(bytes, length = bytes.length)
        @bytes = bytes
        rewind(length)
      end

      def rewind(length)
        @length = length
        self.pointer = 0
      end

      def pointer=(position)
        @pointer = position
        @lead = nil
      end

      # A block read into the channel. A buffer channel takes it into its
      # buffer, a file channel hands it out in place of the file.
      def load(block, length)
        return replace(block.dup, length) unless @writable

        @bytes[@base, block.length] = block
        rewind(length)
      end

      def writable? = @writable

      def exhausted?
        @pointer >= @length
      end

      # A file that holds nothing but its error never opened.
      def failed?
        exhausted? && !@error.nil?
      end

      # Each byte lands at the pointer, which wraps within the block.
      def write(bytes)
        @lead = nil
        bytes.each do |byte|
          @bytes[@base + @pointer] = byte
          @pointer = (@pointer + 1) & 0xff
        end
      end

      def read
        return if exhausted?

        byte = @lead || @bytes[@base + @pointer]
        @lead = nil
        @pointer += 1
        [byte, exhausted? && !@error]
      end
    end
  end
end
