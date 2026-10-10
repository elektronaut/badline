# frozen_string_literal: true

require "badline/drive"
require "badline/drive1541/bus"
require "badline/drive1541/cpu"
require "badline/drive1541/serial_port"
require "badline/drive1541/gcr"
require "badline/drive1541/track"
require "badline/drive1541/disk"
require "badline/drive1541/mechanism"
require "badline/drive1541/disk_via"
require "badline/drive1541/saved_state"

module Badline
  # The 1541 disk drive as a machine of its own: a 6502 running the DOS
  # ROM at 1 MHz, with 2 KB of RAM and two VIAs on its bus. Drive::Core
  # clocks it against the host and sleeps through the DOS's idle loop.
  class Drive1541
    include Drive::Core
    include Drive::VIAs
    include SavedState

    CLOCK_HZ = 1_000_000

    # Where the DOS 2.6 idle loop starts over (see Drive::Idle).
    IDLE_LOOP = 0xebff

    def model_name = "1541"

    # +rom+ covers $C000-$FFFF, and defaults to the DOS image in the ROM
    # path. +device+ is the number the jumpers on VIA 1's PB5 and PB6 set,
    # 8 to 11.
    def initialize(rom: nil, host_clock_hz: CLOCK_HZ, device: 8, debug: false)
      @device = device
      @serial_port = SerialPort.new(device:)
      @via1 = VIA.new(start: 0x1800, peripheral: @serial_port)
      @mechanism = Mechanism.new
      @via2 = DiskVIA.new(start: 0x1c00, mechanism: @mechanism)
      @bus = Bus.new(rom: rom || ROM.load("dos1541.rom", 0xc000), via1: @via1, via2: @via2)
      @cpu = CPU.new(@bus, debug:)
      @clock_hz = CLOCK_HZ
      @idle_loop = IDLE_LOOP
      @host_clock_hz = host_clock_hz
      @phase = 0
      @cycles = 0
      @serial_bus = nil
      init_idle(debug)
      # CA1 powers up at the level of a released ATN, without an edge.
      @via1.ca1 = false
      @via1.reset!
      connect(IECBus.new)
    end

    private

    # One drive cycle. The VIAs clock ahead of the CPU, as the C64's chips
    # do, and either one pulls IRQ. Nothing drives NMI on the 1541. The CPU
    # runs whether or not the motor turns, since it answers ATN.
    #
    # The disk mechanism runs first, so BYTE READY lands on the VIA ahead
    # of the CPU's cycle. The CPU samples SO a cycle late: BYTE READY sets
    # V for the next cycle's instruction step.
    #
    # ATN reaches VIA 1's CA1 through the same inverter as PB7, so CA1 goes
    # high as the C64 asserts ATN, as the serial port sees it: from the
    # host cycle after the one that asserts it.
    def step
      so = @mechanism.take_so
      @mechanism.cycle!
      @via1.ca1 = @serial_port.atn_low?
      @via1.cycle!
      @via2.cycle!
      @cpu.irq = @via1.irq? || @via2.irq?
      @cpu.so! if so
      @cpu.cycle!
      @cycles += 1
    end
  end
end
