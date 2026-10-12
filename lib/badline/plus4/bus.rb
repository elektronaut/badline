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
    #
    # The TED fetches through the same banks: the video matrix and the
    # attributes from ROM or RAM at $8000-$FFFF as the CPU sees it, with no
    # I/O in the way (#ted_fetch), and character and bitmap data from RAM,
    # or from ROM with $FF12 bit 2 set, where below $8000 and in an empty
    # bank it finds the last byte on the bus (#ted_pattern_fetch, Plus/4
    # openmem). Each byte it fetches is left on the bus.
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
      # bank latch, by the address's bits 4-7. +acia+ and +user_port+ are
      # nil where the machine has none, and +cassette_sense+ answers in the
      # user port's place on a machine without one (CassetteSense).
      class IOPage
        def initialize(keyboard_port:, acia: nil, user_port: nil, cassette_sense: nil)
          @bus = nil
          @acia = acia
          @user_port = user_port
          @cassette_sense = cassette_sense
          @keyboard_port = keyboard_port
        end

        # The bus whose last byte an empty spot reads and whose bank latch
        # a write to $FDD0-$FDDF sets.
        def connect(bus)
          @bus = bus
        end

        def peek(addr)
          case addr & 0xf0
          when 0x00 then @acia ? @acia.peek(addr) : @bus.data
          when 0x10 then user_port_peek(addr)
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

        private

        def user_port_peek(addr)
          return @user_port.peek(addr) if @user_port
          return @cassette_sense.read(@bus.data) if @cassette_sense

          @bus.data
        end
      end

      # VICE's debug cartridge register at $FDCF, a spot in the I/O page
      # that nothing answers (plus4world forum post 31417). A write there
      # calls the handler with the byte, the exit code the VICE testprogs
      # report. Every other access falls through to the I/O page.
      class DebugRegister
        ADDRESS = 0xfdcf

        def initialize(io, &handler)
          @io = io
          @handler = handler
        end

        def peek(addr) = @io.peek(addr)

        def poke(addr, value)
          return @handler.call(value) if addr == ADDRESS

          @io.poke(addr, value)
        end
      end

      # Page $FE, where a 1551's TCBM interface puts its 6523 TIA: the one
      # that talks to drive 9 at $FEC0-$FEDF and drive 8's at $FEE0-$FEFF.
      # The rest of the page, and a place with no TIA, is open.
      class TCBMPage
        # The TIA at $FEE0-$FEFF and the one at $FEC0-$FEDF, or nil.
        attr_accessor :drive8, :drive9

        def initialize(bus)
          @bus = bus
          @drive8 = nil
          @drive9 = nil
        end

        def peek(addr)
          return @bus.data if addr < 0xfec0

          tia = addr < 0xfee0 ? @drive9 : @drive8
          tia ? tia.peek(addr) : @bus.data
        end

        def poke(addr, value)
          return if addr < 0xfec0

          tia = addr < 0xfee0 ? @drive9 : @drive8
          tia&.poke(addr, value)
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

      # +io+ is the IOPage, +model+ a Model profile, whose KERNAL it maps
      # and whose function ROMs it maps where the model has them, and
      # +ram_kb+ the RAM fitted.
      def initialize(ted:, port:, io:, model: Model::PLUS4, ram_kb: model.ram_kb)
        addressable_at(0, length: 2**16)
        size = ram_kb * 1024
        @ram = Memory.new(Array.new(size, RAM_POWER_ON), length: size, start: 0)
        @ram_view = MirroredRAM.new(@ram, size - 1)
        @ted = ted
        @open_bus = OpenBus.new(self)
        @low_roms = [ROM.load("plus4/basic.rom", 0x8000), nil, nil, nil]
        @high_roms = [ROM.load(model.kernal, 0xc000), nil, nil, nil]
        if model.plus4_parts
          @low_roms[1] = ROM.load("plus4/function-low.rom", 0x8000)
          @high_roms[1] = ROM.load("plus4/function-high.rom", 0xc000)
        end
        @zero_page = ZeroPage.new(port, @ram_view)
        @io_page = io
        io.connect(self)
        @top_page = TopPage.new(self, ted)
        @tcbm_page = TCBMPage.new(self)
        @debug_register = nil
        @data = 0
        @read_pages = Array.new(256, @open_bus)
        @write_pages = Array.new(256, @ram_view)
        @ted_pages = Array.new(256, @ram_view)
        @ted_rom_pages = Array.new(256, @open_bus)
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

      # Whether the CPU reads the KERNAL at $C000-$FFFF: ROM selected, with
      # the KERNAL's bank, high bank 0.
      def kernal_selected? = @rom_selected && @high_bank.zero?

      # A write to the ROM bank latch at +addr+.
      def select_banks(addr)
        @low_bank = addr & 0x03
        @high_bank = (addr >> 2) & 0x03
        map_reads
      end

      # Calls the block with each byte written to $FDCF (DebugRegister).
      def install_debug_register(&)
        @debug_register = DebugRegister.new(@io_page, &)
        map_writes
      end

      # Plugs in a 1551's TCBM interface, the TIAs at $FEC0-$FEFF.
      def plug_tcbm(drive8:, drive9:)
        @tcbm_page.drive8 = drive8
        @tcbm_page.drive9 = drive9
      end

      # Puts +tia+ where the TCBM interface for +device+, 8 or 9, answers,
      # or takes the one there out with nil.
      def plug_tia(device, tia)
        if device == 9
          @tcbm_page.drive9 = tia
        else
          @tcbm_page.drive8 = tia
        end
      end

      # Puts a cartridge's ROM chips in their slots, as a PLUS4 CARTRIDGE
      # .crt numbers them: a chip's bank picks cartridge 1 (0) or 2 (1), in
      # ROM banks 2 and 3, and its address the low ($8000) or the high
      # ($C000) slot. A chip shorter than 16K repeats through the slot.
      # Slots the chips don't name keep what they held.
      def attach_cartridge(chips)
        chips.each do |chip|
          raise ArgumentError, "no Plus/4 cartridge slot in bank #{chip.bank}" unless chip.bank.between?(0, 1)

          rom = chip.data
          length = rom.length
          data = Array.new(0x4000) { |i| length.zero? ? 0xff : rom[i % length] }
          if chip.address < 0xc000
            @low_roms[2 + chip.bank] = ROM.new(data, length: 0x4000, start: 0x8000)
          else
            @high_roms[2 + chip.bank] = ROM.new(data, length: 0x4000, start: 0xc000)
          end
        end
        map_reads
      end

      # Empties both cartridges' slots, ROM banks 2 and 3, which then read
      # as the open bus.
      def detach_cartridges
        @low_roms[2] = @low_roms[3] = @high_roms[2] = @high_roms[3] = nil
        map_reads
      end

      # The slots that hold a cartridge's ROM, by xplus4's names: c1lo,
      # c1hi, c2lo and c2hi.
      def cartridge_slots
        slots = []
        slots << "c1lo" unless @low_roms[2].nil?
        slots << "c1hi" unless @high_roms[2].nil?
        slots << "c2lo" unless @low_roms[3].nil?
        slots << "c2hi" unless @high_roms[3].nil?
        slots
      end

      def peek(addr)
        @data = @read_pages[addr >> 8].peek(addr)
      end

      def poke(addr, value)
        @data = value
        @write_pages[addr >> 8].poke(addr, value)
      end

      # A TED fetch of the video matrix or the attributes.
      def ted_fetch(addr)
        @data = @ted_pages[addr >> 8].peek(addr)
      end

      # A TED fetch of character or bitmap data, from ROM when +rom+.
      def ted_pattern_fetch(addr, rom)
        @data = rom ? @ted_rom_pages[addr >> 8].peek(addr) : @ram_view.peek(addr)
      end

      private

      def map_writes
        @write_pages[0x00] = @zero_page
        @write_pages[0xfd] = @debug_register || @io_page
        @write_pages[0xfe] = @tcbm_page
        @write_pages[0xff] = @top_page
      end

      def map_reads
        @read_pages.fill(@ram_view, 0x00, 0xfd)
        @read_pages[0x00] = @zero_page
        map_roms(@read_pages) if @rom_selected
        @top_memory = @rom_selected ? @high_roms[@high_bank] || @open_bus : @ram_view
        @read_pages[0xfd] = @io_page
        @read_pages[0xfe] = @tcbm_page
        @read_pages[0xff] = @top_page
        map_ted_reads
      end

      def map_ted_reads
        @ted_pages.fill(@ram_view, 0x80, 0x80)
        map_roms(@ted_pages) if @rom_selected
        map_roms(@ted_rom_pages)
        @ted_pages.fill(@high_roms[@high_bank] || @open_bus, 0xfd, 3) if @rom_selected
        @ted_rom_pages.fill(@high_roms[@high_bank] || @open_bus, 0xfd, 3)
      end

      def map_roms(pages)
        pages.fill(@low_roms[@low_bank] || @open_bus, 0x80, 0x40)
        pages.fill(@high_roms[@high_bank] || @open_bus, 0xc0, 0x3c)
        pages[0xfc] = @high_roms[0]
      end
    end
  end
end
