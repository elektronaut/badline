# frozen_string_literal: true

require "badline/chips/ted"
require "badline/chips/tia"
require "badline/plus4/model"
require "badline/plus4/cpu"
require "badline/plus4/cpu_port"
require "badline/plus4/keyboard_port"
require "badline/plus4/user_port"
require "badline/plus4/cassette_sense"
require "badline/plus4/acia"
require "badline/plus4/bus"

module Badline
  # The Commodore 264 series: the Plus/4, the C16 and the C116. A 7501 on
  # the TED's clock, which runs it once or twice a TED cycle (Chips::TED's
  # Beam), the TED and, on the Plus/4, a 6551 ACIA and the user port's
  # 6529. Only the TED pulls IRQ, and nothing pulls NMI, which the 7501
  # doesn't have.
  #
  # The TED paints the picture a front end shows (#video, #timing). Device 8
  # serves disks through the KERNAL traps (C64::KernalTraps), or a true
  # 1541 or 1581 on the serial bus does (C64::TrueDrives), cartridges go
  # in cartridge 1's slots, and tapes play on the datasette, whose read
  # line's level the KERNAL times with the TED's timers.
  class Plus4
    include IntegerHelper
    include Machine::KeyboardBuffer
    include Machine::Clocking
    include C64::TrueDrives
    include C64::KernalTraps

    # The cycle by which the KERNAL has booted and BASIC printed READY,
    # with a margin, in TED cycles. READY is up by about 116,000 on a PAL
    # Plus/4, 126,000 on an NTSC one and sooner on a C16.
    INIT_THRESHOLD = 200_000

    # The cycle by which a 1541 switched on with the machine has run its
    # DOS's reset, the RAM test and the ROM checksum, and waits on the
    # bus, with a margin, in TED cycles.
    DRIVE_BOOT_CYCLES = 1_200_000

    attr_reader :model, :bus, :cpu, :ted, :sound, :port, :keyboard, :keyboard_port, :joystick1, :joystick2, :acia,
                :user_port, :datasette, :tias, :iec_bus, :cycles, :ram_kb, :drive1541, :init_threshold

    def family = :plus4

    # The joysticks reach the TED's keyboard latch, so there are no C64
    # control ports to plug a pot device into.
    def control_ports = nil

    def ram = @bus.ram

    # What a front end plays: the TED's sound, which answers #record and
    # #drain_samples.
    def sound_source = @sound

    # The chip whose #display a front end shows.
    def video = @ted

    # The TED's clock and raster, and the part of its picture xplus4 shows:
    # all 384 pixels of a line, and 288 lines from line 276 on PAL or 242
    # from line 248 on NTSC, running on past the frame's last line to its
    # first, as the top border is the end of the frame. The TED draws 8
    # pixels a cycle, so each shows one window pixel wide, as on the C64.
    def timing
      profile = @ted.profile
      ntsc = profile == Chips::TED::NTSC
      Timing.new(clock_hz: profile.clock_hz, cycles_per_line: Chips::TED::Beam::CYCLES_PER_LINE,
                 lines_per_frame: ntsc ? 262 : 312, crop: ntsc ? [0, 248, 384, 242] : [0, 276, 384, 288],
                 pixel_width: 1)
    end

    # Reads and writes memory as the CPU sees it, through the bus.
    def peek(addr) = @bus.peek(addr)

    def poke(addr, value) = @bus.poke(addr, value)

    # +model+ names one of Model::ALL, or c116 for the C16, and +ram+ the
    # RAM in K, one of Model::RAM_SIZES, when not the model's own. +tcbm+
    # plugs in a 1551's TCBM interface, the TIAs at $FEC0-$FEFF, with no
    # drive answering on the other side.
    def initialize(model: "plus4", ram: nil, tcbm: false, debug: false)
      @model = Model.named(model)
      @ram_kb = ram || @model.ram_kb
      raise ArgumentError, "no Plus/4 RAM size of #{@ram_kb}K" unless Model::RAM_SIZES.include?(@ram_kb)

      @ted = Chips::TED.new(@model.ted)
      @keyboard = Input::Keyboard.new(matrix: KeyboardPort::MATRIX)
      @joystick1 = Input::Joystick.new
      @joystick2 = Input::Joystick.new
      @keyboard_port = KeyboardPort.new(@keyboard, @joystick1, @joystick2)
      @ted.keyboard_port = @keyboard_port
      @iec_bus = Drives::SerialBus.new
      @datasette = Drives::Datasette.new(level: true)
      @port = CPUPort.new(serial_bus: @iec_bus, datasette: @datasette)
      plus4_parts = @model.plus4_parts
      @acia = plus4_parts ? ACIA.new : nil
      @user_port = plus4_parts ? UserPort.new(@datasette) : nil
      io = Bus::IOPage.new(keyboard_port: @keyboard_port, acia: @acia, user_port: @user_port,
                           cassette_sense: plus4_parts ? nil : CassetteSense.new(@datasette))
      @bus = Bus.new(ted: @ted, port: @port, io:, model: @model, ram_kb: @ram_kb)
      @ted.connect(@bus)
      @tias = tcbm ? [Chips::TIA.new, Chips::TIA.new] : []
      @bus.plug_tcbm(drive8: @tias[0], drive9: @tias[1]) if tcbm
      @cpu = CPU.new(@bus, debug:)
      @cycles = 0
      @sound = Chips::TED::Sound.new(self, @model.ted.clock_hz)
      @ted.sound = @sound
      @init_handlers = []
      @pending_keys = nil
      @dos = nil
      @serial_trap = nil
      @save_trap = nil
      @capture_output = nil
      @drive1541 = nil
      @drive1581 = nil
      @init_threshold = INIT_THRESHOLD
    end

    # One TED cycle: the TED moves on and decides the CPU's clock, then the
    # CPU runs its cycles in it, none while the TED holds the bus.
    def cycle!
      handle_init if @cycles == @init_threshold
      feed_keyboard if @pending_keys

      ted = @ted
      ted.cycle!
      @datasette.cycle!
      @cpu.irq = ted.irq?
      slots = ted.cpu_slots
      if slots.zero?
        @cpu.stall!
      else
        clock_cpu(ted)
        clock_cpu(ted) if slots == 2
      end
      @drive1541&.host_cycle!
      @drive1581&.host_cycle!

      @cycles += 1
    end

    # The RESET line: the CPU, the port, the 6529s, the ACIA, the bank
    # latch and ROM selection, and through the serial bus's RESET line, the
    # drives. The TED has no reset pin.
    def reset!
      @port.reset!
      @keyboard_port.reset!
      @user_port&.reset!
      @dos&.reset!
      @drive1541&.reset!
      @drive1581&.reset!
      @acia&.reset!
      @tias.each(&:reset!)
      @bus.reset!
      @cpu.reset!
    end

    # Switches the machine off and on: RAM, the TED and its sound start
    # from their power-on state, and the RES line resets everything else.
    def power_cycle!
      @bus.power_on!
      @ted.power_on!
      @sound.power_on!
      reset!
    end

    # Calls the block with the exit code a VICE testprog writes to $FDCF.
    def install_debug_register(&) = @bus.install_debug_register(&)

    # Puts a cartridge's ROM chips in cartridge 1's slots (Bus#attach_cartridge)
    # and switches the machine off and on, as a cartridge goes in with the
    # power off. The KERNAL starts it at reset when it signs itself with CBM
    # at $8007.
    def attach_cartridge(chips)
      @bus.attach_cartridge(chips)
      power_cycle!
    end

    # Stores a PRG's bytes from its load address on, into RAM, and returns
    # that address.
    def load_prg(data)
      load_addr = uint16(data[0], data[1])
      bytes = data[2..] || []
      bytes = bytes[0, 0x10000 - load_addr] if load_addr + bytes.length > 0x10000
      bytes.each_with_index { |byte, i| @bus.ram_view.poke(load_addr + i, byte) }
      load_addr
    end

    private

    # The 264 KERNAL's keyboard buffer.
    def keyboard_buffer = Machine::KeyboardBuffer::PLUS4_LAYOUT

    # The 264 KERNAL, which the traps stand in for.
    def trap_layout = KernalTrap::PLUS4_LAYOUT

    def trap_bus = @bus

    # A drive that powers on with the machine takes longer to boot than
    # the KERNAL, and doesn't answer the bus until it has, so the
    # machine's on_init handlers wait for it too.
    def drive1541_attached
      @init_threshold = [@init_threshold, DRIVE_BOOT_CYCLES].max if @cycles < @init_threshold
    end

    def drive1581_attached
      @init_threshold = [@init_threshold, Drives::Model1581::BOOT_CYCLES].max if @cycles < @init_threshold
    end

    # BA stops the CPU at a read, and a write goes ahead.
    def clock_cpu(ted)
      ted.ba_low? && !@cpu.pending_write? ? @cpu.stall! : @cpu.cycle!
    end
  end
end
