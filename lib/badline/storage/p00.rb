# frozen_string_literal: true

module Badline
  module Storage
    module P00
      MAGIC = "C64File\x00".bytes.freeze
      HEADER_SIZE = 26

      class << self
        def wraps?(bytes)
          bytes[0, 8] == MAGIC
        end

        def name(bytes)
          Storage.ascii(bytes[8, 16].take_while(&:positive?)).downcase
        end

        def data(bytes)
          bytes[HEADER_SIZE..]
        end

        # The load address of the program in a .prg file, or wrapped in a
        # .p00 one, or -1 when the file is too short to have one.
        def load_address(path)
          bytes = File.binread(path).bytes
          offset = wraps?(bytes) ? HEADER_SIZE : 0
          bytes.size >= offset + 2 ? bytes[offset] | (bytes[offset + 1] << 8) : -1
        end
      end
    end
  end
end
