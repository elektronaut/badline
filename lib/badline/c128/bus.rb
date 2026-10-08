# frozen_string_literal: true

module Badline
  class C128
    # The 8502's bus in C64 mode, where the 8721 PLA decodes $01's LORAM,
    # HIRAM and CHAREN and the cartridge's EXROM and GAME as a C64's does
    # (AddressBus::PLA), over bank 0 of the 128K of RAM:
    #
    # $D000-$D3FF - the VIC-IIe
    # $D400-$D4FF - the SID, with no mirrors above it
    # $D500-$D5FF - nothing: the MMU is hidden in C64 mode
    # $D600-$D6FF - the VDC
    # $D700-$D7FF - nothing, but for VICE's debug register at $D7FF
    # $D800-$DBFF - colour RAM
    # $DC00-$DCFF - CIA 1
    # $DD00-$DDFF - CIA 2
    # $DE00-$DFFF - I/O 1 and 2, for cartridges
    #
    # An empty page reads the byte the VIC fetched in the preceding phi1
    # half-cycle, as I/O 1 and 2 do on the C64.
    class Bus
      include Addressable
      include AddressBus::PLA
      include AddressBus::ROMs

      # The 8502's port has seven pins. P0-P5 are the 6510's, and P6 senses
      # the CAPS LOCK key, high while it is up. Bit 7 has no pin, and holds
      # the charge last driven onto it, as the 6510's floating bits do.
      PORT_PULLUPS  = 0b0001_0111
      PORT_FLOATING = 0b1000_1000
      CAPS_LOCK     = 0b0100_0000
      TAPE_SENSE    = 0b0001_0000

      # The C64's power-on pattern (AddressBus::RAM_POWER_ON) in both 64K
      # banks. The C128's own DRAMs' pattern is unmeasured.
      RAM_POWER_ON = Array.new(2**17) { |addr| AddressBus::RAM_POWER_ON[addr & 0xffff] }.freeze

      # The VIC's write side: a write to $D02F also drives the extra
      # keyboard lines K0-K2 onto the keyboard's rows 8-10.
      class VICWrites
        def initialize(vic, control_ports)
          @vic = vic
          @control_ports = control_ports
        end

        def peek(addr) = @vic.peek(addr)

        def poke(addr, value)
          @vic.poke(addr, value)
          @control_ports.extra_rows = 0xf8 | @vic.extra_keyboard_lines if (addr & 0x3f) == 0x2f
        end
      end

      # The $D7xx page with VICE's debug register at $D7FF: a write there
      # hands the handler its byte, and the rest of the page is empty.
      class DebugPage
        ADDRESS = 0xd7ff

        def initialize(open_bus, &handler)
          @open_bus = open_bus
          @handler = handler
        end

        def peek(addr) = @open_bus.peek(addr)

        def poke(addr, value)
          @handler.call(value) if addr == ADDRESS
        end
      end

      attr_reader :io_port, :ram, :mmu, :vic, :sid, :vdc, :color_ram, :cia1, :cia2, :keyboard, :joystick1,
                  :joystick2, :control_ports, :cartridge, :ultimax, :phi1_ultimax, :datasette, :region

      # Whether CAPS LOCK is down, holding P6 low.
      attr_reader :caps_lock

      # The chips +model+, a Model::Profile, names, with the SID
      # +sid_model+.
      def initialize(model, sid_model: model.sid_model)
        @region = model.region
        @ram = Memory.new(RAM_POWER_ON, length: 2**17, start: 0)
        @mmu = MMU.new
        @cartridge = nil
        @debug_page = nil
        @caps_lock = false

        load_roms
        plug_chips(model, sid_model)

        @datasette = Datasette.new
        @datasette.on_flag { @cia1.flag! }
        @datasette.on_sense_change { @io_port.value = port_value }

        @color_ram = ColorMemory.new(@vic)
        @vic.vic_bank.connect(cia2: @cia2, color_ram: @color_ram)
        @vic.vic_bank.map_character_rom(character_rom)
        @vic_writes = VICWrites.new(@vic, @control_ports)
        @open_bus = AddressBus::OpenBus.new(@vic)

        @port_ddr = 0x00
        @port_out = 0x00
        @port_floating = 0x00
        @io_port = PortStatus.new(%i[basic kernal io tape_out tape_switch tape_motor], value: port_value)

        @read_pages = Array.new(256)
        @write_pages = Array.new(256)
        @address = 0
        @data = 0
        @io_mapped = false
        update_overlays!
      end

      def attach_cartridge(cartridge)
        @cartridge = cartridge
        cartridge.connect(ram: @ram, open_bus: @open_bus)
        cartridge.on_change { update_overlays! }
        update_overlays!
      end

      # Takes the cartridge out of the expansion port.
      def detach_cartridge
        @cartridge = nil
        update_overlays!
      end

      def power_on!
        @ram.clear!(RAM_POWER_ON)
      end

      # The RES line clears the port's direction and output registers and
      # resets the MMU. The port's floating bit keeps its charge.
      def reset!
        @mmu.reset!
        @port_ddr = 0x00
        @port_out = 0x00
        update_port!
      end

      # Holds CAPS LOCK down, or lets it up.
      def caps_lock=(down)
        @caps_lock = down
        @io_port.value = port_value
      end

      def install_debug_register(&)
        @debug_page = DebugPage.new(@open_bus, &)
        update_overlays!
      end

      # The address and the byte of the CPU's last access, which a VIC-IIe
      # in FAST mode fetches in place of its own, and which tells the
      # machine when an access reached I/O.
      attr_reader :address, :data

      def peek(addr)
        @address = addr
        @data = if addr > 0x01
                  @read_pages[addr >> 8].peek(addr)
                else
                  addr.zero? ? @port_ddr : @io_port.value
                end
      end

      # Whether the last access went to a chip at $D000-$DFFF, which runs
      # at 1 MHz.
      def io_access? = @io_mapped && (@address & 0xf000) == 0xd000

      # Whether the last access went to the VIC's registers.
      def vic_access? = @io_mapped && (@address & 0xfc00) == 0xd000

      # A write to $00 or $01 goes to the port, and the RAM below takes the
      # byte the VIC fetched in the phi1 half of the cycle.
      def poke(addr, value)
        @address = addr
        @data = value
        if addr < 0x02
          @ram.poke(addr, @vic.phi1_data)
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

      def plug_chips(model, sid_model)
        @keyboard = Keyboard.new(matrix: KEYBOARD_MATRIX)
        @joystick1 = Joystick.new
        @joystick2 = Joystick.new
        @control_ports = ControlPorts.new(keyboard: @keyboard, joystick1: @joystick1, joystick2: @joystick2)
        @vic = VIC.new(model: model.vic_model, region: @region)
        @cia1 = CIA.new(start: 0xdc00, peripheral: @control_ports, model: model.cia_model, region: @region)
        @cia2 = CIA.new(start: 0xdd00, model: model.cia_model, region: @region)
        @control_ports.port_a_source = @cia1
        @cia1.on_port_b4_change { |high| @vic.lightpen_level(high) }
        @sid = SID.new(model: sid_model, pots: @control_ports)
        @vdc = VDC.new(model: model.vdc_model, ram_kb: model.vdc_ram_kb, clock_hz: @region.clock_hz)
      end

      def update_port!
        driven = @port_ddr & PORT_FLOATING
        @port_floating = (@port_floating & ~driven) | (@port_out & driven)
        @io_port.value = port_value
        @datasette.motor = !@io_port.tape_motor?
        update_overlays!
      end

      def port_value
        input = PORT_PULLUPS | (@port_floating & PORT_FLOATING)
        input |= CAPS_LOCK unless @caps_lock
        input &= ~TAPE_SENSE if @datasette.sense_low?
        (@port_out & @port_ddr) | (input & ~@port_ddr & 0xff)
      end

      def update_overlays!
        @ultimax = @cartridge ? @cartridge.ultimax? : false
        @phi1_ultimax = @cartridge ? @cartridge.phi1_ultimax? : false
        @vic.vic_bank.map(@ram, base: @mmu.vic_bank << 16, phi1_ultimax: @phi1_ultimax, ultimax: @ultimax,
                                romh: @cartridge&.romh)
        map_pla_pages
      end

      def map_ram_pages
        @io_mapped = false
        @read_pages.fill(@ram)
        @write_pages.fill(@ram)
      end

      def map_io_pages
        @io_mapped = true
        @read_pages.fill(@vic, 0xd0, 4)
        @write_pages.fill(@vic_writes, 0xd0, 4)
        @read_pages[0xd4] = @write_pages[0xd4] = @sid
        @read_pages[0xd5] = @write_pages[0xd5] = @open_bus
        @read_pages[0xd6] = @write_pages[0xd6] = @vdc
        @read_pages[0xd7] = @write_pages[0xd7] = @debug_page || @open_bus
        @read_pages.fill(@color_ram, 0xd8, 4)
        @write_pages.fill(@color_ram, 0xd8, 4)
        @read_pages[0xdc] = @write_pages[0xdc] = @cia1
        @read_pages[0xdd] = @write_pages[0xdd] = @cia2
        @read_pages.fill(@open_bus, 0xde, 2)
        @write_pages.fill(@open_bus, 0xde, 2)
        map_cartridge_io if @cartridge
      end
    end
  end
end
