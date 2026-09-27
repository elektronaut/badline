# frozen_string_literal: true

module Badline
  module KernalTrap
    class Drive
      # A channel open for writing a file. It gathers the bytes sent to it,
      # and the drive writes the file to the disk when the channel closes.
      # An append starts from the file's end, a replace writes over the
      # file of the same name.
      class WriteFile
        attr_accessor :buffer
        attr_reader :name, :type, :mode

        def initialize(name, type, mode: :write)
          @name = name
          @type = type
          @mode = mode
          @bytes = []
        end

        def write(bytes) = @bytes.concat(bytes)

        def writable? = true

        def failed? = false

        # A file open for writing has nothing to send.
        def read = nil

        # Writes the gathered bytes to the storage.
        def store(storage)
          if @mode == :append
            storage.append_file(@name, @bytes, type: @type)
          else
            storage.write_file(@name, @bytes, type: @type, replace: @mode == :replace)
          end
        end
      end
    end
  end
end
