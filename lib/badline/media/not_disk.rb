# frozen_string_literal: true

module Badline
  module Media
    # A file that goes in device 8 but isn't a disk image or a directory.
    class NotDisk < ArgumentError; end
  end
end
