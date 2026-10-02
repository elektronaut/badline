# frozen_string_literal: true

require "badline/address_bus/saved_state"
require "badline/address_bus/sid_slots"
require "badline/address_bus/extra_sids"
require "badline/address_bus/ultimax_pages"

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
    include UltimaxPages
    include ExtraSIDs

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

    # RAM powers on in runs of $00 $00 $FF $FF $FF $FF $00 $00, inverted in
    # the second and fourth 16K: a C64C (ASSY 250469 R4) from
    # C64/raminitpattern/readme.txt, without its occasional random bytes.
    # See doc/pinned-behaviour.md.
    RAM_POWER_ON = Array.new(2**16) { |addr| (((addr + 2) / 4) ^ (addr / 0x4000)).odd? ? 0xff : 0x00 }.freeze

    attr_reader :io_port, :ram, :basic_rom, :character_rom, :kernal_rom,
                :vic, :sid, :color_ram, :cia1, :cia2, :keyboard, :joystick1, :joystick2,
                :control_ports, :cartridge, :ultimax, :phi1_ultimax, :datasette, :region, :video_ram, :reu

    # ram_expansion fits a +60K (:plus60k) or +256K (:plus256k).
    def initialize(sid_model: :mos6581, cia_model: :mos6526, vic_model: :mos6569, region: Region::PAL,
                   ram_expansion: nil)
      @region = region
      @ram = Memory.new(RAM_POWER_ON, length: 2**16, start: 0)
      @ram_expansion = RAMExpansion.build(ram_expansion, @ram) { update_overlays! }
      @cartridge = @reu = nil
      @debug_register = nil

      @basic_rom     = ROM.load("basic.rom",     0xa000)
      @character_rom = ROM.load("character.rom", 0xd000)
      @kernal_rom    = ROM.load("kernal.rom",    0xe000)

      @keyboard = Keyboard.new
      @joystick1 = Joystick.new
      @joystick2 = Joystick.new
      @control_ports = ControlPorts.new(keyboard: @keyboard, joystick1: @joystick1, joystick2: @joystick2)
      @vic  = VIC.new(self, model: vic_model, region:)
      @cia1 = CIA.new(start: 0xdc00, peripheral: @control_ports, model: cia_model, region:)
      @cia2 = CIA.new(start: 0xdd00, model: cia_model, region:)
      @control_ports.port_a_source = @cia1
      @cia1.on_port_b4_change { |high| @vic.lightpen_level(high) }
      @sid = SID.new(model: sid_model, pots: @control_ports)
      @sid_slots = []

      @datasette = Datasette.new
      @datasette.on_flag { @cia1.flag! }
      @datasette.on_sense_change { @io_port.value = port_value }

      @color_ram = ColorMemory.new(@vic)
      @open_bus = OpenBus.new(@vic)
      @cpu_off_bus = false

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

    # An REU takes I/O 2 unless a cartridge claims it, and watches writes
    # to $FF00 for the one that starts an armed transfer.
    def attach_reu(reu)
      @reu = reu
      update_overlays!
    end

    def power_on!
      @ram.clear!(RAM_POWER_ON)
      @ram_expansion.power_on!
    end

    # The RES line clears the 6510 port's direction and output registers,
    # and a RAM expansion's bank register. The port's floating bits keep
    # their charge.
    def reset!
      @ram_expansion.reset!
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

    # A write to $00 or $01 goes to the port, but the RAM below is still
    # write-enabled, and takes whatever is left on the bus: the byte the VIC
    # fetched in the phi1 half of the cycle.
    def poke(addr, value)
      if addr < 0x02
        @ram.poke(addr, @vic.phi1_data)
        addr.zero? ? @port_ddr = value : @port_out = value
        update_port!
      elsif !@cpu_off_bus
        @write_pages[addr >> 8].poke(addr, value)
      end
    end

    # Runs a CPU cycle with the CPU off the bus, as an REU's /DMA line
    # holds it: a write it makes reaches nothing but its own port.
    def cycle_cpu_off_bus(cpu)
      @cpu_off_bus = true
      cpu.cycle!
      @cpu_off_bus = false
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
      @ram_expansion.map(@read_pages, @write_pages)
      @video_ram = @ram_expansion.video_ram

      @ultimax ? map_ultimax_pages : map_banked_pages
      @write_pages[0xff] = @reu.trigger.wrap(@write_pages[0xff]) if @reu
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

    def map_io_pages
      {
        vic => 0xd0..0xd3, sid => 0xd4..0xd7, color_ram => 0xd8..0xdb,
        cia1 => 0xdc..0xdc, cia2 => 0xdd..0xdd, @open_bus => 0xde..0xdf
      }.each do |chip, pages|
        pages.each { |p| @read_pages[p] = @write_pages[p] = chip }
      end
      @ram_expansion.map_io(@read_pages, @write_pages)
      @read_pages[0xd7] = @write_pages[0xd7] = @debug_register if @debug_register
      @read_pages[0xdf] = @write_pages[0xdf] = @reu if @reu
      map_cartridge_io if @cartridge
      map_extra_sids unless @sid_slots.empty?
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
