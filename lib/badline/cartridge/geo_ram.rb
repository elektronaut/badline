# frozen_string_literal: true

module Badline
  class Cartridge
    # GEO-RAM: a RAM expansion on the expansion port, seen through a 256-byte
    # window at $DE00-$DEFF. Two write-only registers pick the page the
    # window shows: $DFFE selects one of the 64 pages of a 16K block, and
    # $DFFF selects the block. As in VICE, the registers answer at every
    # address from $DF80 up, even for $DFFE and odd for $DFFF, and the block
    # number wraps at the number of blocks the RAM holds. Reads of I/O 2 are
    # open bus. It leaves EXROM and GAME high, and RES clears both
    # registers.
    class GeoRAM < Cartridge
      SIZES = [64, 128, 256, 512, 1024, 2048, 4096].freeze
      BLOCK_SIZE = 0x4000
      PAGE_MASK = 0x3f

      attr_reader :size

      # size is the RAM in kilobytes.
      def initialize(size: 512)
        raise ArgumentError, "Unsupported GEO-RAM size #{size}K" unless SIZES.include?(size)

        @size = size
        @block_mask = ((size * 1024) / BLOCK_SIZE) - 1
        super(Storage::CRTFile::Image.new(hardware_type: nil, subtype: 0, exrom: 1, game: 1,
                                          name: "GEO-RAM", chips: []))
      end

      def readable_io_pages
        [0xde]
      end

      def peek(addr)
        @ram_data[@window + (addr & 0xff)]
      end

      def poke(addr, value)
        if addr <= 0xdeff
          @ram_data[@window + (addr & 0xff)] = value
        elsif addr >= 0xdf80
          if addr.odd?
            @block = value & @block_mask
          else
            @page = value & PAGE_MASK
          end
          @window = (@block * BLOCK_SIZE) + (@page * 0x100)
        end
      end

      def reset
        @block = @page = @window = 0
      end

      private

      def install_chips(_chips)
        @ram_data = Array.new(@size * 1024, 0)
        reset
      end
    end
  end
end
