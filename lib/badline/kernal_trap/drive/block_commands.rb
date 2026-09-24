# frozen_string_literal: true

module Badline
  module KernalTrap
    class Drive
      # The commands that read and write a block through a buffer channel,
      # and B-P, which moves its pointer.
      module BlockCommands
        private

        def block_read(arguments, counted: false)
          channel, _drive, track, sector = arguments
          data = fetch_block(channel, track, sector)
          return unless data

          buffer = @channels[channel]
          buffer.load(data, counted ? data[0] + 1 : data.length)
          buffer.pointer = 1 if counted
          report_block_error(track, sector)
        end

        # The disk is write-protected, so a block write that gets as far as
        # the disk fails at the block it names.
        def block_write(arguments, counted: false)
          channel, _drive, track, sector = arguments
          return unless fetch_block(channel, track, sector)

          store_count(@channels[channel]) if counted
          report(WRITE_PROTECT_ON, track, sector)
        end

        # B-W first stores the index of the last byte written, the pointer
        # less one but at least 1, as the block's first byte, which leaves
        # the pointer at 1. B-R reads that count back.
        def counted_block_write(arguments)
          block_write(arguments, counted: true)
        end

        def store_count(buffer)
          count = [buffer.pointer - 1, 1].max
          buffer.pointer = 0
          buffer.write([count])
        end

        # Block access needs an open buffer channel, a disk and a block on it.
        # Returns the block, or nil once it has reported why there is none.
        def fetch_block(channel, track, sector)
          return report(NO_CHANNEL) unless @channels[channel]
          return report(DRIVE_NOT_READY) unless @storage.respond_to?(:read_block)

          data = sector && @storage.read_block(track, sector)
          data || report(ILLEGAL_TRACK_OR_SECTOR, track, sector)
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

          buffer.pointer = position.to_i & 0xff
          report(OK)
        end
      end
    end
  end
end
