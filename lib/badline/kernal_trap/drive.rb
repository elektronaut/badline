# frozen_string_literal: true

module Badline
  module KernalTrap
    # The CBM DOS side of the serial bus. Keeps the open channels, the
    # command channel and its status message. `U1` reads a raw block into a
    # buffer channel, which is how block-access loaders bypass the KERNAL's
    # LOAD.
    class Drive
      COMMAND_CHANNEL = 15
      BLOCK_SIZE = 256

      OK = 0
      WRITE_PROTECT_ON = 26
      SYNTAX_ERROR = 30
      FILE_NOT_FOUND = 62
      ILLEGAL_TRACK_OR_SECTOR = 66
      NO_CHANNEL = 70
      DRIVE_NOT_READY = 74

      MESSAGES = {
        OK => " OK",
        20 => "READ ERROR",
        21 => "READ ERROR",
        22 => "READ ERROR",
        23 => "READ ERROR",
        24 => "READ ERROR",
        25 => "WRITE ERROR",
        WRITE_PROTECT_ON => "WRITE PROTECT ON",
        27 => "READ ERROR",
        28 => "WRITE ERROR",
        29 => "DISK ID MISMATCH",
        SYNTAX_ERROR => "SYNTAX ERROR",
        FILE_NOT_FOUND => "FILE NOT FOUND",
        ILLEGAL_TRACK_OR_SECTOR => "ILLEGAL TRACK OR SECTOR",
        NO_CHANNEL => "NO CHANNEL",
        DRIVE_NOT_READY => "DRIVE NOT READY"
      }.freeze

      COMMANDS = {
        /\AU[1A]\s*:?\s*(.*)/i => :block_read,
        /\AB-R\s*:?\s*(.*)/i => :counted_block_read,
        /\AB-P\s*:?\s*(.*)/i => :buffer_pointer,
        /\A[IV]/i => :initialized,
        /\A(?:U[2B]|B-[WAF])/i => :write_protected
      }.freeze

      FILE_TYPES = { "S" => :seq, "P" => :prg, "U" => :usr }.freeze

      def initialize(storage)
        @storage = storage
        @channels = {}
        @status = Channel.new
        report(OK)
      end

      # A name on the command channel is a command, "#" opens a block
      # buffer, anything else opens a file for reading.
      def open(secondary, name)
        if secondary == COMMAND_CHANNEL
          execute(name) unless name.empty?
        elsif name.start_with?("#")
          @channels[secondary] = Channel.new(Array.new(BLOCK_SIZE, 0))
          report(OK)
        else
          open_file(secondary, name)
        end
      end

      # Closing the command channel closes every other channel with it.
      def close(secondary)
        secondary == COMMAND_CHANNEL ? @channels.clear : @channels.delete(secondary)
      end

      def write(secondary, bytes)
        return report(WRITE_PROTECT_ON) unless secondary == COMMAND_CHANNEL

        execute(Storage.ascii(bytes))
      end

      # Returns the next byte and whether it is the channel's last, or nil
      # when there is nothing left to send.
      def read(secondary)
        secondary == COMMAND_CHANNEL ? read_status : @channels[secondary]&.read
      end

      private

      def read_status
        result = @status.read
        report(OK) if result&.last

        result
      end

      def open_file(secondary, name)
        data = @storage.read_file(file_name(name), type: file_type(secondary, name))
        @channels[secondary] = Channel.new(data || [])
        report(data ? OK : FILE_NOT_FOUND)
      end

      # Names can carry trailing ",P,R" type and mode fields.
      def file_name(name)
        Storage.strip_drive_prefix(name).split(",").first.to_s
      end

      # Secondary addresses 0 and 1 are LOAD and SAVE, which only see PRG
      # files. Otherwise the type field picks one, and without it any type
      # matches.
      def file_type(secondary, name)
        return :prg if secondary < 2

        FILE_TYPES[name.split(",")[1].to_s.strip[0]&.upcase]
      end

      def execute(text)
        command = text.strip
        pattern, action = COMMANDS.find { |candidate, _| candidate.match?(command) }
        return report(SYNTAX_ERROR) unless action

        send(action, arguments(pattern.match(command)[1]))
      end

      def arguments(text)
        text.to_s.scan(/\d+/).map(&:to_i)
      end

      def block_read(arguments, counted: false)
        channel, _drive, track, sector = arguments
        buffer = @channels[channel]
        return report(NO_CHANNEL) unless buffer
        return report(DRIVE_NOT_READY) unless @storage.respond_to?(:read_block)

        data = sector && @storage.read_block(track, sector)
        return report(ILLEGAL_TRACK_OR_SECTOR, track, sector) unless data

        buffer.replace(counted ? data[0, data[0] + 1] : data)
        buffer.pointer = 1 if counted
        report_block_error(track, sector)
      end

      # A block the image's error table marks bad still fills the buffer,
      # but the read reports its error, which copy protection checks for.
      def report_block_error(track, sector)
        error = @storage.block_error(track, sector)
        error ? report(error, track, sector) : report(OK)
      end

      # B-R takes the block's first byte as the index of its last one, and
      # hands out the bytes from the second up to there.
      def counted_block_read(arguments)
        block_read(arguments, counted: true)
      end

      def buffer_pointer(arguments)
        channel, position = arguments
        buffer = @channels[channel]
        return report(NO_CHANNEL) unless buffer

        buffer.pointer = position.to_i
        report(OK)
      end

      def initialized(_arguments)
        report(OK)
      end

      def write_protected(_arguments)
        report(WRITE_PROTECT_ON)
      end

      def report(code, track = 0, sector = 0)
        message = format("%<code>02d,%<message>s,%<track>02d,%<sector>02d\r",
                         code:, message: MESSAGES.fetch(code),
                         track: track.to_i, sector: sector.to_i)
        @status.replace(message.bytes)
        nil
      end
    end
  end
end
