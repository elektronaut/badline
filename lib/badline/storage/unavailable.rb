# frozen_string_literal: true

module Badline
  module Storage
    # Stands in for a directory a detached restore leaves out
    # (Snapshot::StateReader): it finds no files and refuses every write
    # as a write-protected disk does.
    class Unavailable
      def path = ""

      def read_file(_name, **) = nil

      def write_file(_name, _bytes, **)
        raise WriteError, WriteError::WRITE_PROTECT_ON
      end

      def append_file(_name, _bytes, **)
        raise WriteError, WriteError::WRITE_PROTECT_ON
      end
    end
  end
end
