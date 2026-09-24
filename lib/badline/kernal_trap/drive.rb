# frozen_string_literal: true

require "badline/kernal_trap/drive/block_commands"
require "badline/kernal_trap/drive/channels"
require "badline/kernal_trap/drive/memory"
require "badline/kernal_trap/drive/parameters"
require "badline/kernal_trap/drive/status"

module Badline
  module KernalTrap
    # The CBM DOS side of the serial bus. Keeps the open channels, the
    # command channel and its status message. `U1` reads a raw block into a
    # buffer channel, which is how block-access loaders bypass the KERNAL's
    # LOAD.
    class Drive
      include BlockCommands

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

      # A U command jumps through the user table at $FFEA, indexed by the
      # low nibble of its second character less one, so UA and UQ are U1.
      # U1 and U2 read and write a block. U3 to U8 run code in the buffer
      # at $0500, and the five entries past the table's end take vectors
      # from the job queue. Neither runs here, so they report OK as a
      # routine that returns does. U9 (UI) takes the NMI vector and U; the
      # IRQ one, which restart the DOS with its RAM intact, except that a
      # + or - after U9 only switches the bus speed. U: takes the reset
      # vector, which runs the RAM test. U0 restores the table.
      USER_TABLE = [:block_read, :block_write, *[:initialized] * 6,
                    :warm_reset, :cold_reset, :warm_reset, *[:initialized] * 5].freeze

      COMMANDS = {
        /\AU[9IY)][+-]/i => :initialized,
        /\AU.\s*:?\s*(.*)/i => :user,
        /\AB-R\s*:?\s*(.*)/i => :counted_block_read,
        /\AB-P\s*:?\s*(.*)/i => :buffer_pointer,
        /\AB-W\s*:?\s*(.*)/i => :counted_block_write,
        /\A[IV]/i => :initialized,
        /\AB-[AF]/i => :write_protected
      }.freeze

      # A drive powers on reporting its DOS version, as a reset does. It
      # takes the RAM of the drive it replaces when the disk changes.
      def initialize(storage, memory = Memory.new)
        @storage = storage
        @channels = Channels.new
        @status = Status.new
        @memory = memory
        memory.storage = storage
        report(DOS_VERSION)
      end

      # A name on the command channel is a command, "#" opens a block
      # buffer, anything else opens a file for reading. The name comes as
      # the bytes sent, because a memory command's arguments are binary.
      def open(secondary, name)
        if secondary == COMMAND_CHANNEL
          command(name.bytes) unless name.empty?
        elsif name.start_with?("#")
          opened = @channels.open_buffer(secondary, Parameters.parse(name[1..]).first, @memory)
          report(opened ? OK : NO_CHANNEL)
        else
          open_file(secondary, Storage.ascii(without_return(name.bytes)))
        end
      end

      # Closing the command channel closes every other channel with it.
      def close(secondary)
        secondary == COMMAND_CHANNEL ? @channels.clear : @channels.close(secondary)
      end

      # A buffer channel takes the bytes into its block. A file channel is
      # open for reading, so writing to it fails as the disk is protected.
      def write(secondary, bytes)
        return command(bytes) if secondary == COMMAND_CHANNEL

        channel = @channels[secondary]
        return unless channel

        channel.writable? ? channel.write(bytes) : report(WRITE_PROTECT_ON)
      end

      # A SAVE the trap hands over whole, to storage that can write files.
      # A write the host refuses fails as a write-protected disk does.
      # Returns whether the file was written.
      def save(name, bytes)
        saved = @storage.write_file(name, bytes)
        saved ? report(OK) : report(WRITE_PROTECT_ON)
        saved
      end

      # Whether data sent on the channel reaches the drive. The command
      # channel always listens, other channels once they are open.
      def listening?(secondary)
        secondary == COMMAND_CHANNEL || @channels.open?(secondary)
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

      # The DOS cuts a name of two or more bytes at a carriage return in
      # its last or second-to-last byte, as PRINT# ends a line with one.
      def without_return(bytes)
        cut = bytes.rindex(0x0d)
        cut && bytes.length > 1 && cut >= bytes.length - 2 ? bytes[0, cut] : bytes
      end

      # Secondary addresses 0 and 1 are LOAD and SAVE, which look for a PRG
      # file unless the name asks for another type. Other channels take any
      # type the name doesn't pin down.
      def open_file(secondary, name)
        file, type = Storage.parse_name(name)
        type ||= :prg if secondary < 2
        return refuse_write(secondary, name, file) if secondary == 1 || mode?(name, "W")
        return refuse_append(secondary, file, type) if mode?(name, "A")

        channel = @channels.open_file(secondary, Channel.for_name(@storage, @memory, secondary, name, type))
        return report(NO_CHANNEL) unless channel

        channel.failed? ? report(*channel.error) : report(OK)
      end

      def mode?(name, mode)
        name.split(",").drop(1).any? { |field| field.strip[0]&.upcase == mode }
      end

      # The disk is write-protected, so an open for writing fails and leaves
      # the channel closed. A name already on the disk fails as FILE EXISTS
      # unless @ asks to replace it, anything else as WRITE PROTECT ON.
      def refuse_write(secondary, name, file)
        @channels.close(secondary)
        return report(FILE_EXISTS) if !name.start_with?("@") && @storage.read_file(file, type: nil)

        report(WRITE_PROTECT_ON, *protected_block(secondary))
      end

      # An A mode open needs the file on the disk. It fails at the file's
      # last block, the first one an append writes back.
      def refuse_append(secondary, file, type)
        @channels.close(secondary)
        return report(FILE_NOT_FOUND) unless @storage.read_file(file, type:)

        report(WRITE_PROTECT_ON, *(@storage.last_block(file, type:) if @storage.respond_to?(:last_block)))
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
        run_command(action, Parameters.parse(pattern.match(command)[1]))
      end

      def command(bytes)
        action = MEMORY_COMMANDS[bytes[0, 3].pack("C*")]
        action ? run_command(action, bytes[3..]) : execute(Storage.ascii(bytes))
      end

      def run_command(action, arguments)
        case action
        when :block_read then block_read(arguments)
        when :block_write then block_write(arguments)
        when :counted_block_write then counted_block_write(arguments)
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

      # M-W takes an address, a count and that many bytes.
      def memory_write(arguments)
        @memory.write(word(arguments), arguments[3, arguments[2].to_i].to_a)
        report(OK)
      end

      # M-R takes an address and a count, and answers on the command
      # channel. Without a count, or with only the carriage return PRINT#
      # ends a line with, it reads one byte.
      def memory_read(arguments)
        count = arguments[2..] == ["\r".ord] ? 1 : arguments.fetch(2, 1)
        count = BLOCK_SIZE if count.zero?
        @status.replace(@memory.read(word(arguments), count))
        nil
      end

      def word(arguments)
        arguments[0].to_i | (arguments[1].to_i << 8)
      end

      def write_protected(_arguments) = report(WRITE_PROTECT_ON)

      def reset(cold:)
        @memory.clear if cold
        @channels.clear
        report(DOS_VERSION)
      end

      def report(...) = @status.report(...)
    end
  end
end
