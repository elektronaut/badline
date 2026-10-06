# frozen_string_literal: true

module Badline
  class Vic20
    # The CPU's bus:
    #
    # $0000-$03FF - 1K of RAM
    # $0400-$0FFF - RAM1-3, 3K of expansion RAM, or nothing
    # $1000-$1FFF - 4K of RAM
    # $2000-$7FFF - BLK1, BLK2 and BLK3, 8K of expansion RAM each, or nothing
    # $8000-$8FFF - the character ROM
    # $9000-$93FF - I/O 0: the VIC and both VIAs (see IO0)
    # $9400-$97FF - colour RAM, 1K by four bits
    # $9800-$9FFF - I/O 2 and I/O 3, for cartridges
    # $A000-$BFFF - BLK5, 8K of expansion RAM, or nothing
    # $C000-$DFFF - the BASIC ROM
    # $E000-$FFFF - the KERNAL ROM
    #
    # The VIC reaches $0000-$1FFF and $8000-$9FFF, the pages where A13 and
    # A14 are both low, over the V-bus, and the CPU reaches them through it
    # too. Elsewhere the CPU is on its own side of the bus.
    #
    # Each side's data lines hold the last byte they carried, so a read
    # from an empty spot finds that byte: the V-bus's in the 3K hole, and
    # the CPU's own in the empty blocks, I/O 2 and I/O 3. Colour RAM drives
    # the low four lines only, and the V-bus's high four come through.
    # Writes to ROM and to empty spots go nowhere.
    class Bus
      include Addressable

      # The pages each expansion block covers, as [first page, count].
      BLOCKS = {
        ram123: [0x04, 0x0c], blk1: [0x20, 0x20], blk2: [0x40, 0x20], blk3: [0x60, 0x20], blk5: [0xa0, 0x20]
      }.freeze

      # The blocks each of the usual RAM expansions fills.
      RAM_CONFIGURATIONS = {
        unexpanded: [],
        "3k": %i[ram123],
        "8k": %i[blk1],
        "16k": %i[blk1 blk2],
        "24k": %i[blk1 blk2 blk3],
        "32k": %i[blk1 blk2 blk3 blk5]
      }.freeze

      # The last byte on the V-bus's data lines, which an empty spot on
      # the VIC's side reads back.
      class VideoOpenBus
        def initialize(bus)
          @bus = bus
        end

        def peek(_addr) = @bus.video_data
        def poke(_addr, _value); end
      end

      # The last byte the CPU moved, which an empty spot on the CPU's side
      # reads back.
      class OpenBus
        def initialize(bus)
          @bus = bus
        end

        def peek(_addr) = @bus.data
        def poke(_addr, _value); end
      end

      # Colour RAM: four bits a cell, under the V-bus's high four lines.
      class ColorRAM
        def initialize(bus)
          @bus = bus
          @cells = Array.new(0x400, 0)
        end

        def peek(addr) = (@bus.video_data & 0xf0) | @cells[addr & 0x3ff]

        def poke(addr, value)
          @cells[addr & 0x3ff] = value & 0x0f
        end

        # The four bits the cell at +addr+ stores.
        def nibble(addr) = @cells[addr & 0x3ff]
      end

      # I/O 0, $9000-$93FF. The VIC answers in $9000-$90FF, its sixteen
      # registers repeated. The VIAs answer all through I/O 0, on the
      # address lines alone: A4 selects VIA 1 and A5 selects VIA 2. Where
      # more than one chip answers a read, each pulls the lines it drives
      # low, so the CPU reads the AND of them, and a write reaches them
      # all. Where none answers, the CPU reads its own open bus.
      class IO0
        def initialize(bus, vic:, via1:, via2:)
          @bus = bus
          @vic = vic
          @via1 = via1
          @via2 = via2
        end

        def peek(addr)
          vic = addr < 0x9100
          return @bus.data unless vic || addr.anybits?(0x30)

          value = vic ? @vic.peek(addr) : 0xff
          value &= @via1.peek(addr) if addr.anybits?(0x10)
          value &= @via2.peek(addr) if addr.anybits?(0x20)
          value
        end

        def poke(addr, value)
          @vic.poke(addr, value) if addr < 0x9100
          @via1.poke(addr, value) if addr.anybits?(0x10)
          @via2.poke(addr, value) if addr.anybits?(0x20)
        end
      end

      attr_reader :ram, :color_ram, :blocks

      # The last byte the CPU read or wrote.
      attr_reader :data

      # The last byte on the V-bus.
      attr_reader :video_data

      # +vic+, +via1+ and +via2+ are the chips in I/O 0, each answering
      # peek and poke with the CPU's address. +blocks+ names the expansion
      # blocks that hold RAM (BLOCKS), and +kernal+ the KERNAL ROM's file.
      def initialize(vic:, via1:, via2:, blocks: [], kernal: "vic20/kernal-pal.rom")
        addressable_at(0, length: 2**16)
        @ram = Memory.new([], length: 0xc000, start: 0)
        @color_ram = ColorRAM.new(self)
        @character_rom = ROM.load("vic20/character.rom", 0x8000)
        @basic_rom = ROM.load("vic20/basic.rom", 0xc000)
        @kernal_rom = ROM.load(kernal, 0xe000)
        @io0 = IO0.new(self, vic:, via1:, via2:)
        @open_bus = OpenBus.new(self)
        @video_open_bus = VideoOpenBus.new(self)
        @data = @video_data = 0
        @read_pages = Array.new(256, @open_bus)
        @write_pages = Array.new(256, @open_bus)
        self.blocks = blocks
      end

      # Fills the expansion blocks named in +names+ with RAM and empties
      # the rest.
      def blocks=(names)
        @blocks = names.dup.freeze
        map_pages
      end

      # Whether +block+ (BLOCKS) holds RAM.
      def ram?(block) = @blocks.include?(block)

      def peek(addr)
        value = @read_pages[addr >> 8].peek(addr)
        @video_data = value if addr.nobits?(0x6000)
        @data = value
      end

      def poke(addr, value)
        @data = value
        @video_data = value if addr.nobits?(0x6000)
        @write_pages[addr >> 8].poke(addr, value)
      end

      private

      def map_pages
        map(@open_bus, 0x00, 0x100)
        @read_pages.fill(@video_open_bus, 0x04, 0x0c)
        map(@ram, 0x00, 0x04)
        map(@ram, 0x10, 0x10)
        BLOCKS.each { |block, pages| map(@ram, pages[0], pages[1]) if ram?(block) }
        @read_pages.fill(@character_rom, 0x80, 0x10)
        map(@io0, 0x90, 0x04)
        map(@color_ram, 0x94, 0x04)
        @read_pages.fill(@basic_rom, 0xc0, 0x20)
        @read_pages.fill(@kernal_rom, 0xe0, 0x20)
      end

      def map(chip, first, count)
        @read_pages.fill(chip, first, count)
        @write_pages.fill(chip, first, count)
      end
    end
  end
end
