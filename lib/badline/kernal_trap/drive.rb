# frozen_string_literal: true

require "badline/kernal_trap/drive/status"

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
      FILE_EXISTS = 63
      ILLEGAL_TRACK_OR_SECTOR = 66
      NO_CHANNEL = 70
      DOS_VERSION = 73
      DRIVE_NOT_READY = 74

      MEMORY_COMMANDS = { "M-W" => :memory_write, "M-R" => :memory_read }.freeze

      RAM_SIZE = 0x800

      # The job queue: a job code for each of five buffers at $00, their
      # track and sector pairs from $06, and the buffers from $0300. A job
      # code is replaced by its result, 1 for success or an error table
      # code: the DOS error less 18, or 15 for DRIVE NOT READY.
      JOBS = 5
      READ_JOB = 0x80
      JOB_OK = 1
      HEADER_NOT_FOUND = 20

      # A U command jumps through the user table at $FFEA, indexed by the
      # low nibble of its second character less one, so UA and UQ are U1.
      # U1 and U2 read and write a block. U3 to U8 run code in the buffer
      # at $0500, and the five entries past the table's end take vectors
      # from the job queue. Neither runs here, so they report OK as a
      # routine that returns does. U9 (UI) takes the NMI vector and U; the
      # IRQ one, which restart the DOS with its RAM intact, except that a
      # + or - after U9 only switches the bus speed. U: takes the reset
      # vector, which runs the RAM test. U0 restores the table.
      USER_TABLE = [:block_read, :write_protected, *[:initialized] * 6,
                    :warm_reset, :cold_reset, :warm_reset, *[:initialized] * 5].freeze

      COMMANDS = {
        /\AU[9IY)][+-]/i => :initialized,
        /\AU.\s*:?\s*(.*)/i => :user,
        /\AB-R\s*:?\s*(.*)/i => :counted_block_read,
        /\AB-P\s*:?\s*(.*)/i => :buffer_pointer,
        /\A[IV]/i => :initialized,
        /\AB-[WAF]/i => :write_protected
      }.freeze

      # A drive powers on reporting its DOS version, as a reset does.
      def initialize(storage)
        @storage = storage
        @channels = {}
        @status = Status.new
        @ram = Array.new(RAM_SIZE, 0)
        report(DOS_VERSION)
      end

      # A name on the command channel is a command, "#" opens a block
      # buffer, anything else opens a file for reading. The name comes as
      # the bytes sent, because a memory command's arguments are binary.
      def open(secondary, name)
        if secondary == COMMAND_CHANNEL
          command(name.bytes) unless name.empty?
        elsif name.start_with?("#")
          @channels[secondary] = Channel.new(Array.new(BLOCK_SIZE, 0))
          report(OK)
        else
          open_file(secondary, Storage.ascii(name.bytes))
        end
      end

      # Closing the command channel closes every other channel with it.
      def close(secondary)
        secondary == COMMAND_CHANNEL ? @channels.clear : @channels.delete(secondary)
      end

      def write(secondary, bytes)
        return command(bytes) if secondary == COMMAND_CHANNEL

        report(WRITE_PROTECT_ON) if listening?(secondary)
      end

      # Whether data sent on the channel reaches the drive. The command
      # channel always listens, other channels once they are open.
      def listening?(secondary)
        secondary == COMMAND_CHANNEL || @channels.key?(secondary)
      end

      # Returns the next byte and whether it is the channel's last, or nil
      # when there is nothing left to send.
      def read(secondary)
        return @status.read if secondary == COMMAND_CHANNEL

        channel = @channels[secondary]
        result = channel&.read
        report(*channel.error) if result && channel.error && channel.exhausted?
        result
      end

      private

      # Secondary addresses 0 and 1 are LOAD and SAVE, which look for a PRG
      # file unless the name asks for another type. Other channels take any
      # type the name doesn't pin down.
      def open_file(secondary, name)
        file, type = Storage.parse_name(name)
        return refuse_write(secondary, name, file) if writing?(secondary, name)

        type ||= :prg if secondary < 2
        channel = @channels[secondary] = Channel.for_file(@storage, file, type)
        channel.exhausted? && channel.error ? report(*channel.error) : report(OK)
      end

      # SAVE's secondary address 1 and a W mode open a file for writing.
      def writing?(secondary, name)
        secondary == 1 || name.split(",").drop(1).any? { |field| field.strip.match?(/\AW/i) }
      end

      # The disk is write-protected, so an open for writing fails and leaves
      # the channel closed. A name already on the disk fails as FILE EXISTS
      # unless @ asks to replace it, anything else as WRITE PROTECT ON.
      def refuse_write(secondary, name, file)
        @channels.delete(secondary)
        return report(FILE_EXISTS) if !name.start_with?("@") && @storage.read_file(file, type: nil)

        report(WRITE_PROTECT_ON, *protected_block(secondary))
      end

      # SAVE's channel fails at the directory block its entry would go to,
      # a W mode open at the disk's header block.
      def protected_block(secondary)
        return [] unless @storage.respond_to?(:header_block)

        secondary == 1 ? @storage.new_entry_block : @storage.header_block
      end

      def execute(text)
        command = text.strip
        pattern, action = COMMANDS.find { |candidate, _| candidate.match?(command) }
        return report(SYNTAX_ERROR) unless action

        action = USER_TABLE[(command.getbyte(1) - 1) & 0x0f] if action == :user
        run_command(action, arguments(pattern.match(command)[1]))
      end

      def arguments(text)
        text.to_s.scan(/\d+/).map(&:to_i)
      end

      def command(bytes)
        action = MEMORY_COMMANDS[bytes[0, 3].pack("C*")]
        action ? run_command(action, bytes[3..]) : execute(Storage.ascii(bytes))
      end

      def run_command(action, arguments)
        case action
        when :block_read then block_read(arguments)
        when :counted_block_read then counted_block_read(arguments)
        when :buffer_pointer then buffer_pointer(arguments)
        when :initialized then report(OK)
        when :write_protected then write_protected(arguments)
        when :cold_reset then reset(cold: true)
        when :warm_reset then reset(cold: false)
        when :memory_write then memory_write(arguments)
        when :memory_read then memory_read(arguments)
        end
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

      # M-W takes an address, a count and that many bytes. Writes past the
      # RAM are dropped, since the rest of the address space is I/O and ROM.
      def memory_write(arguments)
        address = word(arguments)
        arguments[3, arguments[2].to_i].to_a.each.with_index(address) do |byte, target|
          @ram[target] = byte if target < RAM_SIZE
        end
        run_jobs
        report(OK)
      end

      # M-R takes an address and a count, and answers on the command
      # channel. Without a count, or with only the carriage return PRINT#
      # ends a line with, it reads one byte. Only the RAM reads back.
      def memory_read(arguments)
        address = word(arguments)
        count = arguments[2..] == ["\r".ord] ? 1 : arguments.fetch(2, 1)
        count = BLOCK_SIZE if count.zero?
        @status.replace(Array.new(count) { |i| @ram.fetch(address + i, 0) })
        nil
      end

      def word(arguments)
        arguments[0].to_i | (arguments[1].to_i << 8)
      end

      def run_jobs
        JOBS.times do |job|
          next unless @ram[job] == READ_JOB

          track, sector = @ram[6 + (job * 2), 2]
          @ram[job] = read_job(0x300 + (job * BLOCK_SIZE), track, sector)
        end
      end

      def read_job(buffer, track, sector)
        data = @storage.respond_to?(:read_block) && @storage.read_block(track, sector)
        return job_result(HEADER_NOT_FOUND) unless data

        @ram[buffer, BLOCK_SIZE] = data
        job_result(@storage.block_error(track, sector))
      end

      def job_result(error)
        return JOB_OK unless error

        error == DRIVE_NOT_READY ? 15 : error - 18
      end

      def write_protected(_arguments)
        report(WRITE_PROTECT_ON)
      end

      def reset(cold:)
        @ram.fill(0) if cold
        @channels.clear
        report(DOS_VERSION)
      end

      def report(...) = @status.report(...)
    end
  end
end
