# frozen_string_literal: true

module Badline
  module KernalTrap
    class Drive
      # The command channel's side of the drive: the last DOS error with the
      # track and sector it happened at, or the bytes an M-R read. Once its
      # last byte has been read, it holds OK again.
      class Status
        MESSAGES = [20, 21, 22, 23, 24, 27].to_h { |code| [code, "READ ERROR"] }.merge(
          0 => " OK",
          25 => "WRITE ERROR",
          26 => "WRITE PROTECT ON",
          28 => "WRITE ERROR",
          29 => "DISK ID MISMATCH",
          30 => "SYNTAX ERROR",
          62 => "FILE NOT FOUND",
          63 => "FILE EXISTS",
          66 => "ILLEGAL TRACK OR SECTOR",
          70 => "NO CHANNEL",
          73 => "CBM DOS V2.6 1541",
          74 => "DRIVE NOT READY"
        ).freeze

        def initialize
          @channel = Channel.new
        end

        def report(code, track = 0, sector = 0)
          message = format("%<code>02d,%<message>s,%<track>02d,%<sector>02d\r",
                           code:, message: MESSAGES.fetch(code),
                           track: track.to_i, sector: sector.to_i)
          @channel.replace(message.bytes)
          nil
        end

        def replace(bytes)
          @channel.replace(bytes)
        end

        def read
          result = @channel.read
          report(0) if result&.last
          result
        end
      end
    end
  end
end
