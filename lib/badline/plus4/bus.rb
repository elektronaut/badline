# frozen_string_literal: true

module Badline
  class Plus4
    # The CPU's bus:
    #
    # $0000-$0001 - the 7501's port (CPUPort), over RAM
    # $0002-$7FFF - RAM
    # $8000-$BFFF - the low ROM bank, or RAM
    # $C000-$FCFF - the high ROM bank, or RAM; $FC00-$FCFF is always the
    #               KERNAL's while ROM is selected
    # $FD00-$FD0F - the 6551 ACIA (Plus/4 only)
    # $FD10-$FD1F - the user port's 6529 (Plus/4 only)
    # $FD30-$FD3F - the keyboard's 6529 (KeyboardPort)
    # $FDD0-$FDDF - the ROM bank latch
    # $FF00-$FF1F - the TED
    # $FF3E/$FF3F - a write selects ROM or RAM at $8000-$FFFF
    # $FF40-$FFFF - the high ROM bank, or RAM
    #
    # A write to $FF3E selects ROM and one to $FF3F RAM, everywhere in
    # $8000-$FFFF but $FD00-$FF3F, which holds I/O either way. ROM is
    # selected at power-on and reset. A write to ROM goes to the RAM under
    # it. The ROM bank latch takes the address written to, not the byte:
    # bits 0-1 pick the low bank and bits 2-3 the high bank, 0 for BASIC
    # and the KERNAL, 1 for the Plus/4's function ROMs, 2 and 3 for the two
    # cartridges.
    #
    # RAM smaller than 64K repeats through the 64K, as the C16's 16K does
    # without A14 and A15. Where nothing answers, a read finds the last byte
    # on the bus.
    class Bus
      include Addressable

      RAM_POWER_ON = 0x00

      # RAM through a size it repeats at.
      class MirroredRAM
        def initialize(ram, mask)
          @ram = ram
          @mask = mask
        end

        def peek(addr) = @ram.peek(addr & @mask)

        def poke(addr, value)
          @ram.poke(addr & @mask, value)
        end
      end

      # The last byte the CPU moved, which an empty spot reads back.
      class OpenBus
        def initialize(bus)
          @bus = bus
        end

        def peek(_addr) = @bus.data
        def poke(_addr, _value); end
      end

      # Page 0: the port at $00 and $01, RAM above it.
      class ZeroPage
        def initialize(port, ram)
          @port = port
          @ram = ram
        end

        def peek(addr) = addr < 2 ? @port.peek(addr) : @ram.peek(addr)

        def poke(addr, value)
          return @port.poke(addr, value) if addr < 2

          @ram.poke(addr, value)
        end
      end

      # Page $FD: the ACIA, the user port, the keyboard port and the ROM
      # bank latch, by the address's bits 4-7.
      class IOPage
        def initialize(bus, acia:, user_port:, keyboard_port:)
          @bus = bus
          @acia = acia
          @user_port = user_port
          @keyboard_port = keyboard_port
        end

        def peek(addr)
          case addr & 0xf0
          when 0x00 then @acia ? @acia.peek(addr) : @bus.data
          when 0x10 then @user_port ? @user_port.peek(addr) : @bus.data
          when 0x30 then @keyboard_port.peek(addr)
          else @bus.data
          end
        end

        def poke(addr, value)
          case addr & 0xf0
          when 0x00 then @acia&.poke(addr, value)
          when 0x10 then @user_port&.poke(addr, value)
          when 0x30 then @keyboard_port.poke(addr, value)
          when 0xd0 then @bus.select_banks(addr)
          end
        end
      end

      # Page $FF: the TED in $FF00-$FF3F, its two phantom registers, and
      # ROM or RAM above.
      class TopPage
        def initialize(bus, ted)
          @bus = bus
          @ted = ted
        end

        def peek(addr)
          return @ted.peek(addr) if addr < 0xff40

          @bus.top_memory.peek(addr)
        end

        def poke(addr, value)
          return @bus.ram_view.poke(addr, value) if addr >= 0xff40

          case addr
          when 0xff3e then @bus.rom_selected = true
          when 0xff3f then @bus.rom_selected = false
          else @ted.poke(addr, value)
          end
        end
      end

      attr_reader :ram, :ram_view, :data, :low_bank, :high_bank

      # What the top page reads above $FF3F: the high ROM bank or RAM.
      attr_reader :top_memory

      # The CPU sees ROM at $8000-$FFFF.
      attr_reader :rom_selected

      # +ram_kb+ is the RAM fitted, +kernal+ the KERNAL ROM's file, and
      # +plus4_parts+ whether the function ROMs, the ACIA and the user port
      # are fitted.
      def initialize(ted:, port:, keyboard_port:, ram_kb: 64, kernal: "plus4/kernal-pal.rom", acia: nil,
                     user_port: nil, plus4_parts: true)
        addressable_at(0, length: 2**16)
        size = ram_kb * 1024
        @ram = Memory.new(Array.new(size, RAM_POWER_ON), length: size, start: 0)
        @ram_view = MirroredRAM.new(@ram, size - 1)
        @ted = ted
        @open_bus = OpenBus.new(self)
        @low_roms = [ROM.load("plus4/basic.rom", 0x8000), nil, nil, nil]
        @high_roms = [ROM.load(kernal, 0xc000), nil, nil, nil]
        if plus4_parts
          @low_roms[1] = ROM.load("plus4/function-low.rom", 0x8000)
          @high_roms[1] = ROM.load("plus4/function-high.rom", 0xc000)
        end
        @zero_page = ZeroPage.new(port, @ram_view)
        @io_page = IOPage.new(self, acia:, user_port:, keyboard_port:)
        @top_page = TopPage.new(self, ted)
        @data = 0
        @read_pages = Array.new(256, @open_bus)
        @write_pages = Array.new(256, @ram_view)
        @low_bank = @high_bank = 0
        @rom_selected = true
        @top_memory = @ram_view
        map_writes
        map_reads
      end

      def power_on!
        @ram.clear!(Array.new(@ram.length, RAM_POWER_ON))
        reset!
      end

      # The RESET line selects ROM and the first bank of each.
      def reset!
        @low_bank = @high_bank = 0
        self.rom_selected = true
      end

      def rom_selected=(selected)
        @rom_selected = selected
        @ted.rom_selected = selected
        map_reads
      end

      # A write to the ROM bank latch at +addr+.
      def select_banks(addr)
        @low_bank = addr & 0x03
        @high_bank = (addr >> 2) & 0x03
        map_reads
      end

      def peek(addr)
        @data = @read_pages[addr >> 8].peek(addr)
      end

      def poke(addr, value)
        @data = value
        @write_pages[addr >> 8].poke(addr, value)
      end

      private

      def map_writes
        @write_pages[0x00] = @zero_page
        @write_pages[0xfd] = @io_page
        @write_pages[0xfe] = @open_bus
        @write_pages[0xff] = @top_page
      end

      def map_reads
        @read_pages.fill(@ram_view, 0x00, 0xfd)
        @read_pages[0x00] = @zero_page
        map_roms if @rom_selected
        @top_memory = @rom_selected ? @high_roms[@high_bank] || @open_bus : @ram_view
        @read_pages[0xfd] = @io_page
        @read_pages[0xfe] = @open_bus
        @read_pages[0xff] = @top_page
      end

      def map_roms
        @read_pages.fill(@low_roms[@low_bank] || @open_bus, 0x80, 0x40)
        @read_pages.fill(@high_roms[@high_bank] || @open_bus, 0xc0, 0x3c)
        @read_pages[0xfc] = @high_roms[0]
      end
    end
  end
end
