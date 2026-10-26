# frozen_string_literal: true

require "badline/vic20/attachments"
require "badline/vic20/bus"
require "badline/vic20/cpu"
require "badline/vic20/keyboard_via_ports"
require "badline/vic20/port_wiring"
require "badline/vic20/user_via_ports"
require "badline/snapshot/vic20_setup"
require "badline/vic20/keyed_state"
require "badline/vic20/keyed_modules"

module Badline
  # The Commodore VIC-20, with the PAL 6561 or the NTSC 6560: a 6502 at
  # the VIC's clock, the VIC-I and two 6522 VIAs. VIA 1, at $9110, pulls NMI, and VIA 2, at
  # $9120, pulls IRQ. Nothing else interrupts the CPU, and nothing halts
  # it: the VIC fetches in the half of the cycle the CPU leaves alone.
  #
  # It runs in the window, as `badline vic20`, with the VIC's picture and
  # sound. The keyboard, the joystick and RESTORE reach the VIAs, the
  # datasette and the serial bus hang off them (PortWiring), and device 8
  # serves disks through the KERNAL traps or a true 1541.
  class Vic20
    include IntegerHelper
    include Machine::KeyboardBuffer
    include Machine::Clocking
    include Machine::Settling
    include Attachments
    include PortWiring

    attr_reader :bus, :cpu, :vic, :via1, :via2, :keyboard, :joystick1, :cycles, :init_threshold, :sound,
                :drive1541, :iec_bus, :datasette

    # The RAM expansion it was built with, a key of Bus::RAM_CONFIGURATIONS.
    attr_reader :ram_configuration

    # The model it was built as, one of MODELS.
    attr_reader :model

    # The models, by xvic's names for its video standards: the PAL one with
    # the 6561 and KERNAL 901486-07, and the NTSC one with the 6560 and
    # KERNAL 901486-06.
    MODELS = %w[pal ntsc].freeze

    def ram = @bus.ram

    # Reads and writes memory as the CPU sees it, through the bus.
    def peek(addr) = @bus.peek(addr)

    def poke(addr, value) = @bus.poke(addr, value)

    def family = :vic20

    def portless_board = nil

    # The one control port's joystick, which the front end's second
    # joystick drives too.
    def joystick2 = @joystick1

    # No pot device plugs in yet.
    def control_ports = nil

    # +ram+ names the RAM expansion, one of Bus::RAM_CONFIGURATIONS, and
    # +model+ the model, one of MODELS.
    def initialize(ram: :unexpanded, model: "pal", debug: false)
      @ram_configuration = ram
      @model = model
      raise ArgumentError, "no VIC-20 model named #{model}" unless MODELS.include?(model)

      @vic = Chips::VICI.new(model == "ntsc" ? Chips::VICI::NTSC : Chips::VICI::PAL)
      @keyboard = Input::Keyboard.new(matrix: KeyboardVIAPorts::MATRIX)
      @joystick1 = Input::Joystick.new
      @iec_bus = Drives::SerialBus.new
      @datasette = Drives::Datasette.new
      @via1 = Chips::VIA.new(start: 0x9000, peripheral: UserVIAPorts.new(joystick: @joystick1, serial_bus: @iec_bus,
                                                                         datasette: @datasette))
      keyboard_ports = KeyboardVIAPorts.new(keyboard: @keyboard, joystick: @joystick1)
      @via2 = Chips::VIA.new(start: 0x9000, peripheral: keyboard_ports)
      keyboard_ports.connect(@via2)
      @bus = Bus.new(vic: @vic, via1: @via1, via2: @via2, blocks: Bus::RAM_CONFIGURATIONS.fetch(ram),
                     kernal: "vic20/kernal-#{model}.rom")
      @vic.connect(@bus)
      @cpu = CPU.new(@bus, debug:)
      @cpu.power_on!
      @cycles = 0
      @sound = Chips::VICI::Sound.new(self, @vic.profile.clock_hz)
      @vic.sound = @sound
      @nmi_asserted = false
      @init_handlers = []
      @pending_keys = nil
      @init_keys = nil
      @dos = nil
      @serial_trap = nil
      @save_trap = nil
      @capture_output = nil
      @drive1541 = nil
      @drive1581 = nil
      @init_threshold = boot_cycles
      wire_ports
    end

    # The VIC and the VIAs clock ahead of the CPU, as the C64's chips do,
    # so a register write lands on the cycle after the one it was issued
    # on.
    def cycle!
      handle_init if @cycles == @init_threshold
      feed_keyboard if @pending_keys

      @vic.cycle!
      @via1.cycle!
      @via2.cycle!
      @datasette.cycle!
      @cpu.irq = @via2.irq?
      drive_nmi
      @cpu.cycle!
      @drive1541&.host_cycle!
      @drive1581&.host_cycle!

      @cycles += 1
    end

    # The chip whose #display a front end shows.
    def video = @vic

    # What a front end plays: the VIC's sound, which answers #record and
    # #drain_samples.
    def sound_source = @sound

    # The VIC's clock and raster, and the part of the display xvic shows:
    # every pixel of a line, from line 28, below the VIC's vertical blank,
    # 284 lines on PAL and 233 on NTSC. The VIC draws 4 pixels a cycle,
    # half as many as the C64's VIC-II on about the same clock, so each
    # pixel shows two window pixels wide, as xvic draws them.
    def timing
      profile = @vic.profile
      width = profile.cycles_per_line * Chips::VICI::PIXELS_PER_CYCLE
      blanked = profile.blanked_lines
      Timing.new(clock_hz: profile.clock_hz, cycles_per_line: profile.cycles_per_line,
                 lines_per_frame: profile.lines_per_frame,
                 crop: [0, blanked, width, profile.shown_lines], pixel_width: 2, dots: 1)
    end

    # The RESTORE key pulls VIA 1's CA1 low while it is held. The KERNAL
    # sets CA1 to interrupt on that falling edge, and its NMI handler
    # ($FEAD) warm-starts BASIC if RUN/STOP is down too.
    def press_restore
      @via1.ca1 = false
    end

    def release_restore
      @via1.ca1 = true
    end

    # Calls the block with the exit code a VICE testprog writes to $910F.
    def install_debug_register(&) = @bus.install_debug_register(&)

    # Stores a PRG's bytes from its load address on, as the CPU would, so
    # bytes for an empty block go nowhere, and returns that address.
    def load_prg(data)
      load_addr = uint16(data[0], data[1])
      bytes = data[2..] || []
      bytes = bytes[0, 0x10000 - load_addr] if load_addr + bytes.length > 0x10000
      bytes.each_with_index { |byte, i| @bus.poke(load_addr + i, byte) }
      load_addr
    end

    # The RES line reaches the CPU and both VIAs, and through the serial
    # bus's RESET line, the drive. The VIC has no reset pin.
    def reset!
      @via1.reset!
      @via2.reset!
      via_written
      @dos&.reset!
      @drive1541&.reset!
      @drive1581&.reset!
      @nmi_asserted = false
      @cpu.reset!
    end

    # Switches the machine off and on: RAM and the VIC start from their
    # power-on state, and the RES line resets everything else.
    def power_cycle!
      @bus.power_on!
      @vic.power_on!
      @sound.power_on!
      reset!
    end

    private

    # The cycle by which the KERNAL has booted and BASIC printed READY,
    # with a margin. The KERNAL's RAM test takes most of it, and runs up
    # from $1000 until it finds no RAM, so each 8K block on from BLK1
    # adds about 615,000 cycles. Unexpanded, READY is up by about 557,000.
    def boot_cycles
      tested = 0
      tested += 1 while tested < 3 && @bus.ram?(%i[blk1 blk2 blk3][tested])
      700_000 + (650_000 * tested)
    end

    # VIA 1's IRQ output drives NMI, and the CPU takes an interrupt on its
    # falling edge.
    def drive_nmi
      nmi = @via1.irq?
      @cpu.nmi = true if nmi && !@nmi_asserted
      @nmi_asserted = nmi
    end
  end
end
