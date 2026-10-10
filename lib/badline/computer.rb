# frozen_string_literal: true

require "badline/computer/common"
require "badline/computer/true_drives"
require "badline/computer/attachments"
require "badline/computer/kernal_traps"
require "badline/computer/saved_state"

module Badline
  class Computer
    include IntegerHelper
    include KeyboardBuffer
    include Machine::Clocking
    include Common
    include Attachments
    include KernalTraps
    include SavedState

    attr_reader :address_bus, :cpu, :cycles, :drive1541

    # The path of the disk or directory device 8 serves through the traps
    # (Attachments), or an empty one.
    def mounted_path = @drive.nil? ? "" : @drive.path

    def family = :c64

    def region = address_bus.region

    def vic = address_bus.vic

    def cia1 = address_bus.cia1

    def cia2 = address_bus.cia2

    def sid = address_bus.sid

    def ram = address_bus.ram

    def keyboard = address_bus.keyboard

    def joystick1 = address_bus.joystick1

    def joystick2 = address_bus.joystick2

    def control_ports = address_bus.control_ports

    def datasette = address_bus.datasette

    def install_debug_register(&) = address_bus.install_debug_register(&)

    # The machine options (sid_model:, cia_model:, vic_model:, region: and
    # ram_expansion:) configure the AddressBus. The region sets the clock,
    # the VIC's raster and sprite timing, and the mains frequency the CIAs'
    # TOD clocks count. The KERNAL tells PAL from NTSC by the raster, so
    # every region boots the same ROMs. reu plugs an REU of that many K
    # into the expansion port, where it drives the IRQ line and takes the
    # bus for its transfers. kernal:, datasette: and board: fit the bus
    # afterwards (AddressBus::Fittings): the KERNAL ROM, the cassette port,
    # which is empty on the SX-64, and the board and case.
    def initialize(debug: false, reu: nil, **machine)
      @address_bus = AddressBus.new(**machine.except(*AddressBus::Fittings::NAMES))
      @address_bus.fit(**machine.slice(*AddressBus::Fittings::NAMES))
      @cpu = CPU.new(@address_bus, debug:)
      @vic = @address_bus.vic
      @vic.open_bus = -> { @address_bus.ram.peek(@cpu.program_counter) }
      @cia1 = @address_bus.cia1
      @cia2 = @address_bus.cia2
      @sid = @address_bus.sid
      @datasette = @address_bus.datasette
      @cycles = 0
      @nmi_asserted = false
      @cartridge_nmi = false
      @restore_pulse = false
      @reu_irq = false
      @dma = false
      @freezing = false
      @freeze_writes = 0
      @init_handlers = []
      @pending_keys = nil
      @drive = nil
      @serial_trap = nil
      @save_trap = nil
      @drive1541 = nil
      @drive1581 = nil
      plug_serial_bus
      @reu = reu ? plug_reu(reu) : nil
    end

    INIT_THRESHOLD = 2_500_000

    def cycle!
      handle_init if @cycles == INIT_THRESHOLD
      feed_keyboard if @pending_keys

      # The chips clock ahead of the CPU, so a register write lands on the
      # cycle after the one it was issued on.
      @vic.cycle!
      @cia1.cycle!
      @cia2.cycle!
      @sid.cycle!
      @datasette.cycle!

      @cpu.irq = @cia1.interrupted? || @vic.interrupted? || @reu_irq

      drive_nmi
      watch_freeze if @freezing
      clock_cpu
      @drive1541&.host_cycle!
      @drive1581&.host_cycle!

      @cycles += 1
    end

    # The cycle at which #on_init's handlers run, once the KERNAL has booted.
    def init_threshold
      INIT_THRESHOLD
    end

    # The chip whose #display a front end shows.
    def video = @vic

    # The chip a front end records the machine's sound from.
    def sound_source = @sid

    def attach_cartridge(cartridge)
      connect_cartridge(cartridge)
      power_cycle!
    end

    def reu = address_bus.reu

    # A cartridge goes in with the power off, so attaching one switches the
    # machine off and on: the VIC and RAM start from their power-on state,
    # and the RES line resets everything else.
    def power_cycle!
      vic.power_on!
      address_bus.power_on!
      reset!
    end

    # The RES line reaches the CPU and its port, both CIAs, the SID, the
    # cartridge port, a RAM expansion and, through the serial bus's RESET
    # line, the drive. The VIC has no reset pin.
    def reset!
      address_bus.reset!
      @cia1.reset!
      @cia2.reset!
      @sid.reset!
      address_bus.cartridge&.reset
      @reu&.reset!
      @dma = false
      @drive&.reset!
      @drive1541&.reset!
      @drive1581&.reset!
      @freezing = false
      @nmi_asserted = false
      cpu.reset!
    end

    # Presses the cartridge's freeze button. When the press pulls NMI, the
    # cartridge freezes once the CPU takes the interrupt.
    def press_cartridge_button
      cartridge = address_bus.cartridge
      return unless cartridge

      cartridge.press_button
      @freezing = cartridge.nmi?
      @freeze_writes = 0
    end

    def release_cartridge_button
      address_bus.cartridge&.release_button
    end

    # RESTORE isn't in the key matrix. It fires a one-shot that pulses the
    # NMI line however long the key is held, modelled here as one cycle.
    # A machine without a keyboard has no RESTORE key either.
    def press_restore
      @restore_pulse = true if keyboard.connected?
    end

    # The one-shot has pulsed already, so letting go does nothing.
    def release_restore; end

    def capture_output
      @capture_output ||= ChroutTrap.new(cpu:, bus: address_bus, layout: KernalTrap::C64_LAYOUT).tap do |trap|
        cpu.install_trap(ChroutTrap::ADDRESS) { trap.call }
      end
    end

    private

    # The KERNAL the traps stand in for (Attachments#mount).
    def trap_layout = KernalTrap::C64_LAYOUT

    def plug_reu(size_kb)
      reu = REU.new(size_kb, bus: @address_bus, vic: @vic)
      reu.on_irq_change { |level| @reu_irq = level }
      reu.on_dma { @dma = true }
      @address_bus.attach_reu(reu)
      reu
    end

    # BA halts the CPU on a read cycle, and so does an REU holding the bus
    # for a transfer.
    def clock_cpu
      return dma_cycle! if @dma

      @cpu.pending_write? || !@vic.ba_low? ? @cpu.cycle! : @cpu.stall!
    end

    # The REU's /DMA line takes the bus from the CPU from the cycle after
    # it asks for it, even while it waits for BA, but RDY only halts the
    # CPU on a read, so a write it makes then goes nowhere.
    def dma_cycle!
      writing = @cpu.pending_write?
      @reu.dma_cycle!(@vic.ba_low?)
      return writing ? @address_bus.cycle_cpu_off_bus(@cpu) : @cpu.stall! if @reu.dma?

      @dma = false
      writing || !@vic.ba_low? ? @cpu.cycle! : @cpu.stall!
    end

    # A freezer counts the CPU's write cycles once it pulls NMI and switches
    # to Ultimax on the third in a row, the last push of the interrupt
    # sequence, so the vector fetch that follows reads the cartridge.
    def watch_freeze
      @freeze_writes = @cpu.pending_write? ? @freeze_writes + 1 : 0
      return if @freeze_writes < 3

      @freezing = false
      address_bus.cartridge.freeze!
    end
  end
end
