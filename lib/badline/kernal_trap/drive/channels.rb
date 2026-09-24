# frozen_string_literal: true

module Badline
  module KernalTrap
    class Drive
      # The drive's open data channels by secondary address, and the five
      # buffers they hold. The DOS hands out the highest free buffer.
      # Reading the BAM when it initializes the disk takes buffer 4, so
      # channels get 3 down to 0, and the fifth data channel finds none.
      class Channels
        BAM_BUFFER = 4

        def initialize
          @channels = {}
        end

        def [](secondary) = @channels[secondary]

        def open?(secondary) = @channels.key?(secondary)

        def close(secondary) = @channels.delete(secondary)

        def clear = @channels.clear

        # Opens a buffer channel on the buffer a "#n" name asks for, or on
        # the highest free one. Returns nil when that buffer isn't free,
        # which leaves a channel asking again for its own buffer open.
        def open_buffer(secondary, number, memory)
          return if number && !free_buffers.include?(number)

          close(secondary)
          number ||= free_buffers.max
          @channels[secondary] = Channel.buffer(memory, number) if number
        end

        # A file that opens takes a buffer, though its bytes don't pass
        # through drive RAM here. One that fails to open takes none. Returns
        # nil, leaving the channel closed, when no buffer is free.
        def open_file(secondary, channel)
          close(secondary)
          channel.buffer = free_buffers.max unless channel.failed?
          @channels[secondary] = channel if channel.failed? || channel.buffer
        end

        private

        def free_buffers
          (0...BAM_BUFFER).to_a - @channels.values.map(&:buffer)
        end
      end
    end
  end
end
