# frozen_string_literal: true

require "badline/c128/model"
require "badline/c128/mmu"
require "badline/c128/vdc"
require "badline/c128/bus"
require "badline/c128/cpu"

module Badline
  # The Commodore 128 in C64 mode: the 8502 on the VIC-IIe's clock, two
  # CIAs, the SID, the VDC's registers and RAM, and 128K of RAM, of which
  # C64 mode sees bank 0 through the 8721 PLA. It runs the C64's BASIC and
  # KERNAL, so the C64's KERNAL traps, the keyboard buffer and CHROUT
  # capture work unchanged.
  #
  # It powers on in C64 mode, the state the C128 KERNAL reaches when C= is
  # held at power-on, without the Z80's boot or C128 mode (MMU).
  #
  # Where a C64 program sees it differ from a C64C: the 8502's P6 senses CAPS
  # LOCK, $D02F drives the extra keyboard rows, $D030's FAST bit runs the
  # CPU at 2 MHz and its TEST bit races the raster counter, the SID has no
  # mirrors, and $D500-$D7FF holds the hidden MMU, the VDC and open bus.
  class C128
    include IntegerHelper
    include KeyboardBuffer
    include Computer::Attachments

    # The C64's 8x8 matrix and the three rows K0-K2 select, in port B
    # column order.
    KEYBOARD_MATRIX = (Keyboard::C64_MATRIX + [
      %i[help keypad8 keypad5 tab keypad2 keypad4 keypad7 keypad1],
      %i[esc keypad_plus keypad_minus line_feed keypad_enter keypad6 keypad9 keypad3],
      %i[alt keypad0 keypad_period crsr_up crsr_down crsr_left crsr_right no_scroll]
    ]).freeze

    attr_reader :cpu, :cycles, :drive1541, :model

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

    # :c64, until C128 mode boots.
    def mode = @bus.mmu.mode

    def install_debug_register(&) = @bus.install_debug_register(&)

    # +model+ names one of Model::ALL, and +sid_model+, when not nil, the
    # SID in place of the model's.
    def initialize(model: "c128", sid_model: nil, debug: false)
      @model = Model.named(model)
      @bus = Bus.new(@model, sid_model: sid_model || @model.sid_model)
      @cpu = CPU.new(@bus, debug:)
      @vic = @bus.vic
      @vic.open_bus = -> { @bus.ram.peek(@cpu.program_counter) }
      @cia1 = @bus.cia1
      @cia2 = @bus.cia2
      @sid = @bus.sid
      @datasette = @bus.datasette
      @cycles = 0
      @clock_bits = 0
      @nmi_asserted = false
      @cartridge_nmi = false
      @restore_pulse = false
      @init_handlers = []
      @pending_keys = nil
      @drive = nil
      @serial_trap = nil
      @save_trap = nil
      @drive1541 = nil
      @capture_output = nil
      plug_serial_bus
      enter_c64_mode
    end

    # The chips clock ahead of the CPU, as on the C64. $D030's FAST and
    # TEST bits take hold a cycle after the write that sets them: in FAST
    # mode the CPU runs in both halves of the cycle (#clock_fast), and the
    # TEST bit steps the raster counter in every cycle.
    def cycle!
      handle_init if @cycles == Computer::INIT_THRESHOLD
      feed_keyboard if @pending_keys

      clock_bits = @clock_bits
      @clock_bits = @vic.clock_bits
      @vic.test_step! if clock_bits >= 0x02

      @vic.cycle!
      @cia1.cycle!
      @cia2.cycle!
      @sid.cycle!
      @datasette.cycle!

      @cpu.irq = @cia1.interrupted? || @vic.interrupted?

      drive_nmi
      clock_bits.odd? ? clock_fast : clock_cpu
      @drive1541&.host_cycle!

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

    # The cycle at which #on_init's handlers run, once the C64 KERNAL has
    # booted.
    def init_threshold = Computer::INIT_THRESHOLD

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

    # The chip whose #display a front end shows.
    def video = @vic

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

    # RAM and the VIC start from their power-on state, and the RES line
    # resets everything else.
    def power_cycle!
      @vic.power_on!
      @bus.power_on!
      reset!
      enter_c64_mode
    end

    # The RES line reaches the CPU and its port, the MMU, both CIAs, the
    # SID, the cartridge port and, through the serial bus, the drive.
    def reset!
      @bus.reset!
      @cia1.reset!
      @cia2.reset!
      @sid.reset!
      @bus.cartridge&.reset
      @drive&.reset!
      @drive1541&.reset!
      @nmi_asserted = false
      @cpu.reset!
    end

    # RESTORE pulses NMI for a cycle, as on the C64.
    def press_restore
      @restore_pulse = true
    end

    def release_restore; end

    # CAPS LOCK locks down and up, and holds the 8502's P6 low while down.
    def press_caps_lock
      @bus.caps_lock = true
    end

    def release_caps_lock
      @bus.caps_lock = false
    end

    def capture_output
      @capture_output ||= ChroutTrap.new(cpu:, bus: @bus, layout: KernalTrap::C64_LAYOUT).tap do |trap|
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
