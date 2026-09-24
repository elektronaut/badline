# frozen_string_literal: true

module Badline
  # Memory layout:
  #
  # 0x0000-0x00FF - Page 0       - Zeropage
  # 0x0100-0x01FF - Page 1       - Stack
  # 0x0200-0x02FF - Page 2       - OS/BASIC pointers
  # 0x0300-0x03FF - Page 3       - OS/BASIC pointers
  # 0x0400-0x07FF - Page 4-7     - Screen memory
  # 0x0800-0x9FFF - Page 8-159   - BASIC program storage area
  # 0xA000-0xBFFF - Page 160-191 - Machine code program storage (ROM overlay)
  # 0xC000-0xCFFF - Page 192-207 - Machine code program storage
  # 0xD000-0xD3FF - Page 208-211 - VIC II registers
  # 0xD400-0xD7FF - Page 212-215 - SID registers
  # 0xD800-0xDBFF - Page 216-219 - Color memory
  # 0xDC00-0xDCFF - Page 220     - CIA 1
  # 0xDD00-0xDDFF - Page 221     - CIA 2
  # 0xDE00-0xDEFF - Page 222     - I/O 1
  # 0xDF00-0xDFFF - Page 223     - I/O 2
  # 0xE000-0xFFFF - Page 224-255 - Machine code program storage (ROM overlay)

  # Overlays:
  #
  # 0x8000-0x9FFF - Cartridge ROM (low) - 8kb
  # 0xA000-0xBFFF - BASIC ROM / Cartridge ROM (high) - 8kb
  # 0xD000-0xDFFF - Character ROM / I/O - 4kb
  # 0xE000-0xFFFF - KERNAL ROM / Cartridge ROM (high) - 8kb
  class AddressBus
    include Addressable

    # I/O 1 and 2, and the Ultimax holes, with nothing on the bus. A read
    # picks up the byte the VIC fetched in the preceding phi1 half-cycle,
    # and a write goes nowhere.
    class OpenBus
      def initialize(vic)
        @vic = vic
      end

      def peek(_addr) = @vic.phi1_data
      def poke(_addr, _value); end
    end

    PORT_PULLUPS  = 0b0001_0111
    PORT_FLOATING = 0b1100_1000
    TAPE_SENSE    = 0b0001_0000

    RAM_POWER_ON = [0xff, 0x07].freeze

    attr_reader :io_port, :ram, :basic_rom, :character_rom, :kernal_rom,
                :vic, :sid, :color_ram, :cia1, :cia2, :keyboard, :joystick1, :joystick2,
                :control_ports, :cartridge, :ultimax, :phi1_ultimax, :datasette

    def initialize(sid_model: :mos6581, cia_model: :mos6526)
      @ram = Memory.new(RAM_POWER_ON, length: 2**16, start: 0)
      @cartridge = nil
      @debug_register = nil

      @basic_rom     = ROM.load("basic.rom",     0xa000)
      @character_rom = ROM.load("character.rom", 0xd000)
      @kernal_rom    = ROM.load("kernal.rom",    0xe000)

      @keyboard = Keyboard.new
      @joystick1 = Joystick.new
      @joystick2 = Joystick.new
      @control_ports = ControlPorts.new(keyboard: @keyboard, joystick1: @joystick1, joystick2: @joystick2)
      @vic  = VIC.new(self)
      @cia1 = CIA.new(start: 0xdc00, peripheral: @control_ports, model: cia_model)
      @cia2 = CIA.new(start: 0xdd00, model: cia_model)
      @control_ports.port_a_source = @cia1
      @cia1.on_port_b4_change { |high| @vic.lightpen_level(high) }
      @sid = SID.new(model: sid_model, pots: @control_ports)

      @datasette = Datasette.new
      @datasette.on_flag { @cia1.flag! }
      @datasette.on_sense_change { @io_port.value = port_value }

      @color_ram = ColorMemory.new(@vic)
      @open_bus = OpenBus.new(@vic)

      @port_ddr = 0x00
      @port_out = 0x00
      @port_floating = 0x00
      @io_port = PortStatus.new(%i[basic kernal io tape_out tape_switch tape_motor], value: port_value)

      @read_pages = Array.new(256)
      @write_pages = Array.new(256)
      update_overlays!
    end

    def attach_cartridge(cartridge)
      @cartridge = cartridge
      cartridge.connect(ram: @ram, open_bus: @open_bus)
      cartridge.on_change { update_overlays! }
      update_overlays!
    end

    def power_on!
      @ram.clear!(RAM_POWER_ON)
    end

    # The 6510's RES line clears the port's direction and output registers.
    # The floating bits keep their charge.
    def reset_port!
      @port_ddr = 0x00
      @port_out = 0x00
      update_port!
    end

    def disable_overlays!
      poke(0, 0x2f)
      poke(1, 0)
    end

    def install_debug_register(&)
      @debug_register = DebugRegister.new(@sid, &)
      update_overlays!
    end

    def peek(addr)
      return @port_ddr if addr.zero?
      return @io_port.value if addr == 0x01

      @read_pages[addr >> 8].peek(addr)
    end

    def poke(addr, value)
      if addr < 0x02
        addr.zero? ? @port_ddr = value : @port_out = value
        update_port!
      else
        @write_pages[addr >> 8].poke(addr, value)
      end
    end

    def inspect
      "#<#{self.class.name} port=#{format('0x%02x', @io_port.value)} " \
        "cartridge=#{@cartridge ? @cartridge.class.name : 'none'} " \
        "ultimax=#{@ultimax}>"
    end

    private

    def update_port!
      driven = @port_ddr & PORT_FLOATING
      @port_floating = (@port_floating & ~driven) | (@port_out & driven)
      @io_port.value = port_value
      # $01 bit 5 drives the motor through an inverter: low runs it.
      @datasette.motor = !@io_port.tape_motor?
      update_overlays!
    end

    def port_value
      input = PORT_PULLUPS | (@port_floating & PORT_FLOATING)
      input &= ~TAPE_SENSE if @datasette.sense_low?
      (@port_out & @port_ddr) | (input & ~@port_ddr & 0xff)
    end

    # Banking changes only on $01 writes and cartridge line/bank changes,
    # so reads and writes dispatch through per-page handler tables instead
    # of range checks.
    def update_overlays!
      @ultimax = @cartridge ? @cartridge.ultimax? : false
      @phi1_ultimax = @cartridge ? @cartridge.phi1_ultimax? : false
      @read_pages.fill(@ram)
      @write_pages.fill(@ram)

      @ultimax ? map_ultimax_pages : map_banked_pages
    end

    def map_banked_pages
      map_rom_overlays
      map_cartridge_ram
      @write_pages.fill(@cartridge.romh_writes, 0xe0, 0x20) if @cartridge&.romh_writes

      if io?
        map_io_pages
      elsif character?
        @read_pages.fill(character_rom, 0xd0, 0x10)
      end
    end

    # EXROM and GAME select the cartridge whether or not it has a chip
    # there, and an empty socket leaves the bus floating.
    def map_rom_overlays
      @read_pages.fill(@cartridge.roml || @open_bus, 0x80, 0x20) if roml?
      if romh?
        @read_pages.fill(@cartridge.romh || @open_bus, 0xa0, 0x20)
      elsif basic?
        @read_pages.fill(basic_rom, 0xa0, 0x20)
      end
      @read_pages.fill(kernal_rom, 0xe0, 0x20) if kernal?
    end

    # Cartridge RAM in the ROML or ROMH window decodes writes itself,
    # whatever the $01 lines say.
    def map_cartridge_ram
      return unless @cartridge&.exrom&.zero?

      map_cartridge_ram_bank(@cartridge.roml, 0x80)
      map_cartridge_ram_bank(@cartridge.romh, 0xa0) if @cartridge.game.zero?
    end

    def map_cartridge_ram_bank(bank, first_page)
      @write_pages.fill(bank, first_page, 0x20) if bank.is_a?(Cartridge::RAMBank)
    end

    # Ultimax cartridges ignore the $01 lines: 4K of RAM, ROML/ROMH windows,
    # I/O always visible and open address space everywhere else. The ROML
    # and ROMH selects fire on writes as well, so cartridge RAM or flash in
    # either window takes the writes there.
    def map_ultimax_pages
      @read_pages.fill(@open_bus, 0x10, 0xf0)
      @write_pages.fill(@open_bus, 0x10, 0xf0)
      @read_pages.fill(@cartridge.roml, 0x80, 0x20) if @cartridge.roml
      map_ultimax_writes(@cartridge.roml, 0x80)
      @read_pages.fill(@cartridge.romh, 0xe0, 0x20) if @cartridge.romh
      map_ultimax_writes(@cartridge.romh, 0xe0)
      map_ultimax_a000
      map_io_pages
    end

    def map_ultimax_writes(bank, first_page)
      @write_pages.fill(bank, first_page, 0x20) if bank.respond_to?(:poke)
    end

    def map_ultimax_a000
      return unless (window = @cartridge.ultimax_a000)

      @read_pages.fill(window, 0xa0, 0x20)
      @write_pages.fill(window, 0xa0, 0x20)
    end

    def map_io_pages
      {
        vic => 0xd0..0xd3, sid => 0xd4..0xd7, color_ram => 0xd8..0xdb,
        cia1 => 0xdc..0xdc, cia2 => 0xdd..0xdd, @open_bus => 0xde..0xdf
      }.each do |chip, pages|
        pages.each { |p| @read_pages[p] = @write_pages[p] = chip }
      end
      @read_pages[0xd7] = @write_pages[0xd7] = @debug_register if @debug_register
      map_cartridge_io if @cartridge
    end

    def map_cartridge_io
      @write_pages.fill(@cartridge, 0xde, 2)
      @cartridge.readable_io_pages.each { |p| @read_pages[p] = @cartridge }
    end

    def basic?
      io_port.kernal? && io_port.basic? && game_high?
    end

    def game_high?
      @cartridge.nil? || @cartridge.game == 1
    end

    def roml?
      @cartridge&.exrom&.zero? && io_port.kernal? && io_port.basic?
    end

    def romh?
      @cartridge&.exrom&.zero? && @cartridge.game.zero? && io_port.kernal?
    end

    # In 16K mode LORAM alone leaves $d000 as RAM, where it still maps I/O.
    def character?
      (io_port.kernal? || (io_port.basic? && game_high?)) && !io_port.io?
    end

    def io?
      (io_port.basic? || io_port.kernal?) && io_port.io?
    end

    def kernal?
      io_port.kernal?
    end
  end
end
