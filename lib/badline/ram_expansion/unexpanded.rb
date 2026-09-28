# frozen_string_literal: true

module Badline
  module RAMExpansion
    # The machine with no expansion fitted: its own RAM everywhere, and
    # $D100 left to the VIC.
    class Unexpanded
      include Banking

      def initialize(ram)
        @low_ram = @video_ram = @high_ram = ram
        @on_change = nil
      end

      def map_io(_read_pages, _write_pages); end

      def reset!; end

      def power_on!; end
    end
  end
end
