# frozen_string_literal: true

require "badline/c128/model"
require "badline/c128/mmu"
require "badline/c128/vdc"
require "badline/c128/mmu_pages"
require "badline/c128/io_pages"
require "badline/c128/z80_pages"
require "badline/c128/color_lines"
require "badline/c128/banks"
require "badline/c128/bus_state"
require "badline/c128/bus"
require "badline/c128/cpu"
require "badline/c128/z80"
require "badline/c128/z80_turns"
require "badline/c128/saved_state"
require "badline/c128/keys"
require "badline/c128/modes"
require "badline/c128/drives"
require "badline/c128/fast_serial"
require "badline/drive1571"

module Badline
  # The Commodore 128: the 8502 on the VIC-IIe's clock, two CIAs, the SID,
  # the VDC and its 80 column display, and 128K of RAM, which the 8722 MMU
  # maps (C128::Bus).
  #
  # Built for C128 mode, it powers on as the C128 does: the Z80 runs the
  # boot code in its BIOS and hands the bus to the 8502, which then runs
  # its reset vector into BASIC 7.0 and the C128 KERNAL. The KERNAL goes
  # to C64 mode as on the C128, with C= held at reset, a C64 cartridge or
  # GO64. MCR bit 0 hands the bus back and forth from then on, and the
  # Z80 runs 2 T-states in each cycle the VIC leaves it the bus.
  #
  # Built for C64 mode, the default, it powers on in C64 mode, the state
  # the C128 KERNAL reaches when C= is held at power-on, and a reset comes
  # back there. It runs the C64's BASIC and KERNAL, so the C64's KERNAL
  # traps, the keyboard buffer and CHROUT capture work unchanged.
  #
  # Where a C64 program sees it differ from a C64C: the 8502's P6 senses CAPS
  # LOCK, $D02F drives the extra keyboard rows, $D030's FAST bit runs the
  # CPU at 2 MHz and its TEST bit races the raster counter, the SID has no
  # mirrors, and $D500-$D7FF holds the hidden MMU, the VDC and open bus.
  class C128
    include IntegerHelper
    include KeyboardBuffer
    include Computer::Attachments
    include Computer::KernalTraps
    include Keys
    include Modes
    include Drives
    include FastSerial
    include Z80Turns

    # The C64's 8x8 matrix and the three rows K0-K2 select, in port B
    # column order.
    KEYBOARD_MATRIX = (Keyboard::C64_MATRIX + [
      %i[help keypad8 keypad5 tab keypad2 keypad4 keypad7 keypad1],
      %i[esc keypad_plus keypad_minus line_feed keypad_enter keypad6 keypad9 keypad3],
      %i[alt keypad0 keypad_period crsr_up crsr_down crsr_left crsr_right no_scroll]
    ]).freeze

    # The cycle at which #on_init's handlers run, once the KERNAL of the
    # mode the machine is built for has booted: the C64's as on a C64, or
    # BASIC 7.0's, which is READY by then.
    C128_INIT_THRESHOLD = 2_000_000

    # The C128 KERNAL's keyboard buffer and its count.
    C128_KEYBOARD_BUFFER = 0x034a
    C128_KEYBOARD_COUNT = 0xd0

    attr_reader :cpu, :cycles, :drive1541, :model, :init_threshold

    # The path of the disk or directory device 8 serves through the traps
    # (Computer::Attachments), or an empty one.
    def mounted_path = @drive.nil? ? "" : @drive.path

    def family = :c128

    def address_bus = @bus

    def region = @bus.region

    def vic = @bus.vic

    def cia1 = @bus.cia1

    def cia2 = @bus.cia2

    def sid = @bus.sid

    def vdc = @bus.vdc

    def mmu = @bus.mmu

    def ram = @bus.ram

    def keyboard = @bus.keyboard

    def joystick1 = @bus.joystick1

    def joystick2 = @bus.joystick2

    def control_ports = @bus.control_ports

    def datasette = @bus.datasette

    # :c64 or :c128, the mode the MMU is in.
    def mode = @bus.mmu.mode

    def install_debug_register(&) = @bus.install_debug_register(&)

    # +model+ names one of Model::ALL, and +sid_model+, when not nil, the
    # SID in place of the model's. +mode+, :c64 or :c128, is the mode it
    # powers on and resets into.
    def initialize(model: "c128", sid_model: nil, mode: :c64, debug: false)
      raise ArgumentError, "no C128 mode named #{mode}" unless %i[c64 c128].include?(mode)

      @model = Model.named(model)
      @c64_built = mode == :c64
      @init_threshold = @c64_built ? Computer::INIT_THRESHOLD : C128_INIT_THRESHOLD
      @holding_commodore = false
      @bus = Bus.new(@model, sid_model: sid_model || @model.sid_model, mode:)
      @cpu = CPU.new(@bus, debug:)
      build_z80
      @vic = @bus.vic
      @vic.open_bus = -> { @bus.ram.peek(@cpu.program_counter) }
      @cia1 = @bus.cia1
      @cia2 = @bus.cia2
      @sid = @bus.sid
      @vdc = @bus.vdc
      @datasette = @bus.datasette
      @cycles = 0
      @clock_bits = 0
      @nmi_asserted = false
      @cartridge_nmi = false
      @restore_pulse = false
      @init_handlers = []
      @pending_keys = nil
      @capture_output = nil
      init_drives
      enter_c64_mode if @c64_built
      @bus.on_mode_change { mode_changed }
    end

    # The chips clock ahead of the CPU, as on the C64. $D030's FAST and
    # TEST bits take hold a cycle after the write that sets them: in FAST
    # mode the CPU runs in both halves of the cycle (#clock_fast), and the
    # TEST bit steps the raster counter in every cycle.
    def cycle!
      return z80_cycle! if @z80_turn

      handle_init if @cycles == @init_threshold
      feed_keyboard if @pending_keys

      clock_bits = @clock_bits
      @clock_bits = @vic.clock_bits
      @vic.test_step! if clock_bits >= 0x02

      @vic.cycle!
      @cia1.cycle!
      @cia2.cycle!
      @sid.cycle!
      @datasette.cycle!
      @vdc.cycle!

      @cpu.irq = @cia1.interrupted? || @vic.interrupted?

      drive_nmi
      clock_bits.odd? ? clock_fast : clock_cpu
      clock_serial_bus

      @cycles += 1
    end

    # Runs `count` cycles, one #cycle! after another.
    def run_cycles(count)
      i = 0
      while i < count
        cycle!
        i += 1
      end
    end

    # Runs cycles until the block returns true or the cycle count passes
    # `limit`, checking before each cycle.
    def run_until(limit)
      cycle! until yield || @cycles > limit
    end

    def on_init(&block)
      if @cycles < init_threshold
        @init_handlers << block
      else
        block.call
      end
    end

    # The clock, the raster and the crop of the VIC-IIe's region.
    def timing
      region = @bus.region
      Timing.new(clock_hz: region.clock_hz, cycles_per_line: region.cycles_per_line,
                 lines_per_frame: region.lines_per_frame, crop: region.crop, pixel_width: 1)
    end

    # The chip whose #display a front end shows: the VIC-IIe, or with
    # :vdc the VDC, whose display paints only while its #render is on.
    def video(chip = :vic) = chip == :vdc ? @vdc : @vic

    # Renders the VDC's display, and not the VIC-IIe's, while a front end
    # shows it, or with false the other way round.
    def vdc_shown=(shown)
      @vdc.render = shown
      @vic.render = !shown
    end

    # The chip a front end records the machine's sound from.
    def sound_source = @sid

    def load_prg(data)
      uint16(data[0], data[1]).tap do |load_addr|
        ram.write(load_addr, data[2..])
      end
    end

    # A cartridge goes in with the power off.
    def attach_cartridge(cartridge)
      connect_cartridge(cartridge)
      power_cycle!
    end

    # RAM, the VIC and the VDC start from their power-on state, and the RES
    # line resets everything else.
    def power_cycle!
      @vic.power_on!
      @vdc.power_on!
      @bus.power_on!
      reset!
      enter_c64_mode if @c64_built
    end

    # The RES line reaches the CPU and its port, the MMU, both CIAs, the
    # SID, the cartridge port and, through the serial bus, the drives.
    def reset!
      @bus.reset!
      @cia1.reset!
      @cia2.reset!
      @sid.reset!
      @bus.cartridge&.reset
      @drive&.reset!
      @drive1541&.reset!
      @drive1571&.reset!
      @drive1581&.reset!
      @nmi_asserted = false
      reset_z80
    end

    # CHROUT is at $FFD2 in both KERNALs, and the trap follows the mode.
    def capture_output
      @capture_output ||= ChroutTrap.new(cpu:, bus: @bus, layout: trap_layout).tap do |trap|
        cpu.install_trap(ChroutTrap::ADDRESS) { trap.call }
      end
    end

    def inspect
      "#<#{self.class.name} cycles=#{@cycles} cpu=(#{@cpu.inspect})>"
    end

    private

    # The C128 KERNAL leaves $D02F at $FF, every extra keyboard row
    # deselected, before it jumps to the C64's reset.
    def enter_c64_mode
      @vic.poke(0xd02f, 0xff)
      @bus.control_ports.extra_rows = 0xff
    end

    # The NMI line is wired-OR between CIA 2, the cartridge and RESTORE,
    # and the CPU takes an interrupt on its falling edge.
    def drive_nmi
      nmi = @cia2.interrupted? || @cartridge_nmi || @restore_pulse
      @restore_pulse = false
      @cpu.nmi = true if nmi && !@nmi_asserted
      @nmi_asserted = nmi
    end

    # BA halts the CPU on a read cycle.
    def clock_cpu
      @cpu.pending_write? || !@vic.ba_low? ? @cpu.cycle! : @cpu.stall!
    end

    # The 8502 at 2 MHz takes both halves of the cycle, and BA no longer
    # halts it. It leaves phi1 to the VIC in the refresh cycles, and an
    # access to I/O, whose chips run at 1 MHz, waits for phi2. The VIC's
    # fetches in the cycle see the bytes on the bus. In a phi1 the CPU
    # spends waiting that is the byte it writes, or the last byte the bus
    # held.
    def clock_fast
      phi1 = 0xff
      unless @vic.refresh_cycle?
        held = @bus.data
        write = @cpu.pending_write?
        @cpu.cycle!
        if @bus.io_access?
          data = @bus.data
          return @vic.take_cpu_bus(write ? data : held, data, @bus.vic_access?)
        end

        phi1 = @bus.data
      end
      @cpu.cycle!
      @vic.take_cpu_bus(phi1, @bus.data, @bus.vic_access?)
    end

    def handle_init
      @init_handlers.each(&:call)
    end
  end
end
