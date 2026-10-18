# frozen_string_literal: true

module Badline
  class CBM2
    # The 6509's bus: sixteen segments of 64K, which the CPU's four extra
    # address lines pick from the execution register at $0000 or, for the
    # data of LDA (zp),Y and STA (zp),Y, the indirection register at $0001
    # (CPU). Both registers answer at $0000 and $0001 in every segment.
    #
    # Segment 15 is the system's:
    #
    # $0000-$07FF - 2K of static RAM
    # $0800-$0FFF - nothing: the buffer RAM socket
    # $1000-$7FFF - the disk ROM's socket and the cartridge's three 8K
    #               selects, nothing until a ROM is in (#attach_cartridge)
    # $8000-$BFFF - BASIC
    # $C000-$CFFF - nothing
    # $D000-$D7FF - the screen RAM
    # $D800-$DFFF - I/O, a chip a page (#map_io), nothing where none is
    # $E000-$FFFF - the KERNAL
    #
    # The RAM board fills the segments +ram_segments+ names, and the rest
    # hold nothing. The data lines hold the last byte they carried, which
    # a read from nothing finds, and a write to ROM or to nothing goes
    # nowhere.
    #
    # Each segment is a pair of page tables, one read and one write. The
    # CPU reads and writes through the execution segment's (#peek and
    # #poke), and a write to $0000 switches them, so an access pays
    # nothing for the banking. For an indirect access the CPU switches to
    # the indirection segment's tables and back (#select_indirect! and
    # #select_execute!).
    class Bus
      include Addressable

      SEGMENTS = 16
      SYSTEM = 15

      # The last byte the CPU moved, which nothing reads back.
      class OpenBus
        def initialize(bus)
          @bus = bus
        end

        def peek(_addr) = @bus.data
        def poke(_addr, _value); end
      end

      # A segment's page 0: the execution register at $0000 and the
      # indirection register at $0001, whose reads return the register in
      # the low four bits and 0 in the high four, over what the page holds.
      class Registers
        def initialize(bus, under)
          @bus = bus
          @under = under
        end

        def peek(addr)
          case addr
          when 0 then @bus.execution_segment
          when 1 then @bus.indirect_segment
          else @under.peek(addr)
          end
        end

        def poke(addr, value)
          case addr
          when 0 then @bus.execution_segment = value & 0x0f
          when 1 then @bus.indirect_segment = value & 0x0f
          else @under.poke(addr, value)
          end
        end
      end

      # VICE's debug cartridge register at $DAFF in segment 15, which a
      # write calls the handler with, the exit code the VICE testprogs
      # report. Every other write to its page passes to the chip there.
      class DebugRegister
        ADDRESS = 0xdaff

        attr_accessor :under

        def initialize(&handler)
          @handler = handler
          @under = nil
        end

        def poke(addr, value)
          return @handler.call(value) if addr == ADDRESS

          @under.poke(addr, value)
        end
      end

      attr_reader :ram, :screen, :segment_ram, :execution_segment
      attr_accessor :indirect_segment

      # The last byte the CPU read or wrote.
      attr_reader :data

      # +basic+ and +kernal+ are ROM files for $8000-$BFFF and
      # $E000-$FFFF, +ram_segments+ the segments the RAM board fills, and
      # +screen_length+ the bytes of screen RAM from $D000 on.
      def initialize(basic:, kernal:, ram_segments:, screen_length: 0x800)
        addressable_at(0, length: 2**16)
        @ram = Memory.new([], length: 0x800, start: 0)
        @screen = Memory.new([], length: screen_length, start: 0xd000)
        @screen_pages = screen_length >> 8
        @basic_rom = ROM.load(basic, 0x8000)
        @kernal_rom = ROM.load(kernal, 0xe000)
        @open_bus = OpenBus.new(self)
        @data = 0
        @segment_ram = Array.new(SEGMENTS) do |segment|
          ram_segments.include?(segment) ? Memory.new([], length: 0x10000, start: 0) : nil
        end
        @io = Array.new(8, @open_bus)
        @cartridge = []
        @video = Array.new(0x18, nil)
        @video_writable = Array.new(0x18, false)
        @debug_register = nil
        @reads = Array.new(SEGMENTS) { Array.new(256, @open_bus) }
        @writes = Array.new(SEGMENTS) { Array.new(256, @open_bus) }
        reset!
        map_pages
      end

      # The RES line sets both registers to 15.
      def reset!
        self.execution_segment = SYSTEM
        @indirect_segment = SYSTEM
      end

      def power_on!
        @ram.clear!
        @screen.clear!
        @segment_ram.each { |memory| memory&.clear! }
      end

      def execution_segment=(segment)
        @execution_segment = segment
        select_execute!
      end

      # Switches the CPU's accesses to the indirection segment, for the one
      # access LDA (zp),Y or STA (zp),Y moves its data with.
      def select_indirect!
        @read_pages = @reads[@indirect_segment]
        @write_pages = @writes[@indirect_segment]
      end

      # Switches them back to the execution segment.
      def select_execute!
        @read_pages = @reads[@execution_segment]
        @write_pages = @writes[@execution_segment]
      end

      def peek(addr)
        @data = @read_pages[addr >> 8].peek(addr)
      end

      def poke(addr, value)
        @data = value
        @write_pages[addr >> 8].poke(addr, value)
      end

      # Reads and writes +segment+ as the CPU would, wherever it executes.
      def peek_bank(segment, addr) = @reads[segment][addr >> 8].peek(addr)

      def poke_bank(segment, addr, value)
        @writes[segment][addr >> 8].poke(addr, value)
      end

      # Whether the CPU runs the KERNAL: it executes in segment 15.
      def kernal_mapped? = @execution_segment == SYSTEM

      # Puts +chip+ at I/O page +page+, $D8 to $DF of segment 15. The chip
      # hears the whole address.
      def map_io(page, chip)
        @io[page - 0xd8] = chip
        map_pages
      end

      # Puts +chip+ at +count+ pages of segment 15 from +page+ on, between
      # $C000 and $D7FF, over what was there: the P500's character ROM, and
      # its colour RAM, which takes writes as well (+writable+). The chip
      # hears the whole address.
      def map_video(chip, page, count, writable: false)
        count.times do |i|
          @video[page + i - 0xc0] = chip
          @video_writable[page + i - 0xc0] = writable
        end
        map_pages
      end

      # Puts the cartridge's ROM chips, Storage::CRTFile::Chips, at their
      # load addresses in segment 15, from $1000 to $7FFF, in place of what
      # was there.
      def attach_cartridge(chips)
        @cartridge = chips.map { |chip| ROM.new(chip.data, length: chip.data.length, start: chip.address) }
        map_pages
      end

      def detach_cartridge
        @cartridge = []
        map_pages
      end

      # Calls the block with each byte written to $DAFF (DebugRegister).
      def install_debug_register(&)
        @debug_register = DebugRegister.new(&)
        map_pages
      end

      private

      def map_pages
        SEGMENTS.times do |segment|
          memory = @segment_ram[segment]
          if memory
            map(segment, memory, 0x00, 0x100)
          else
            map(segment, @open_bus, 0x00, 0x100)
          end
        end
        map_system
        SEGMENTS.times { |segment| map_registers(segment) }
        select_execute!
      end

      def map_system
        map(SYSTEM, @open_bus, 0x00, 0x100)
        map(SYSTEM, @ram, 0x00, 0x08)
        @cartridge.each { |rom| @reads[SYSTEM].fill(rom, rom.start >> 8, rom.length >> 8) }
        @reads[SYSTEM].fill(@basic_rom, 0x80, 0x40)
        map(SYSTEM, @screen, 0xd0, @screen_pages)
        @video.each_with_index { |chip, i| map_video_page(chip, 0xc0 + i, @video_writable[i]) if chip }
        @io.each_with_index { |chip, i| map(SYSTEM, chip, 0xd8 + i, 1) }
        @reads[SYSTEM].fill(@kernal_rom, 0xe0, 0x20)
        map_debug_register if @debug_register
      end

      def map_video_page(chip, page, writable)
        @reads[SYSTEM][page] = chip
        @writes[SYSTEM][page] = writable ? chip : @open_bus
      end

      def map_registers(segment)
        @reads[segment][0] = Registers.new(self, @reads[segment][0])
        @writes[segment][0] = Registers.new(self, @writes[segment][0])
      end

      def map_debug_register
        @debug_register.under = @writes[SYSTEM][0xda]
        @writes[SYSTEM][0xda] = @debug_register
      end

      def map(segment, chip, first, count)
        @reads[segment].fill(chip, first, count)
        @writes[segment].fill(chip, first, count)
      end
    end
  end
end
