# frozen_string_literal: true

module Badline
  module RAMExpansion
    # The register and page mapping the expansions share. #map lays the
    # selected banks out in the address bus's page tables, and #map_io puts
    # the register over the VIC's I/O page at $D100.
    module Banking
      attr_reader :low_ram, :high_ram, :video_ram

      # The block runs whenever the register moves a bank.
      def on_change(&block)
        @on_change = block
      end

      def peek(_addr) = 0xff

      def map(read_pages, write_pages)
        [read_pages, write_pages].each do |pages|
          pages.fill(@low_ram, 0x00, 0x10)
          pages.fill(@high_ram, 0x10, 0xf0)
        end
      end

      def map_io(read_pages, write_pages)
        read_pages[0xd1] = write_pages[0xd1] = self
      end
    end
  end
end
