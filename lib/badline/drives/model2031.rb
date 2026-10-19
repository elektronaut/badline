# frozen_string_literal: true

require "badline/drives/model1541"
require "badline/drives/ieee_bus"
require "badline/drives/model2031/parts"
require "badline/drives/model2031/ieee_port"
require "badline/drives/model2031/keyed_state"

module Badline
  module Drives
    # The 2031 disk drive of the PET and CBM: the 1541's board with an
    # IEEE-488 interface in place of the serial one (Commodore schematic
    # 2031038). A 6502 at 1 MHz runs DOS 2.6 from 16 KB of ROM, with 2 KB
    # of RAM, VIA 1 at $1800 on the IEEE-488 bus (IEEEPort) and VIA 2 at
    # $1C00 running the 1541's GCR Mechanism, decoded as the 1541's.
    #
    # Drives::Engine::Core clocks it against the host and sleeps through
    # the DOS's idle loop, as the 1541's, until ATN moves or a timer is due
    # (Engine::VIAs). The bus reads the lines it pulls without waking it.
    class Model2031
      include Engine::Core
      include Engine::VIAs

      CLOCK_HZ = 1_000_000

      # Where the DOS's idle loop starts over (see Drives::Engine::Idle).
      IDLE_LOOP = 0xec4d

      # The host cycles by which a 2031 switched on with the machine has run
      # its DOS's RAM test and ROM checksums and reads its jumpers.
      BOOT_CYCLES = 1_300_000

      attr_reader :ieee_bus

      def model_name = "2031"

      def boot_cycles = BOOT_CYCLES

      # Whether the drive is where VICE saves it: its CPU between
      # instructions.
      def settled_for_vice? = cpu.boundary?

      # +rom+ covers $C000-$FFFF, and defaults to the DOS image in the ROM
      # path. +device+ is the number the jumpers set, 8 to 11.
      def initialize(rom: nil, host_clock_hz: CLOCK_HZ, device: 8, debug: false)
        @device = device
        @ieee_bus = IEEEBus.new
        @serial_port = IEEEPort.new(device:, bus: @ieee_bus)
        @via1 = IEEEVIA.new(start: 0x1800, peripheral: @serial_port)
        @serial_port.via = @via1
        @mechanism = Model1541::Mechanism.new
        @via2 = Model1541::DiskVIA.new(start: 0x1c00, mechanism: @mechanism)
        @bus = Bus.new(rom: rom || ROM.load("dos2031.rom", 0xc000), via1: @via1, via2: @via2)
        @cpu = CPU.new(@bus, debug:)
        @clock_hz = CLOCK_HZ
        @idle_loop = IDLE_LOOP
        @host_clock_hz = host_clock_hz
        @phase = 0
        @cycles = 0
        init_idle(debug)
        @via1.ca1 = false
        @via1.reset!
        connect(@ieee_bus)
      end

      # Plugs the drive into an IEEE-488 bus, leaving the one it was on.
      def connect(ieee_bus)
        settle!
        @ieee_bus.detach(self)
        @ieee_bus = ieee_bus
        @serial_port.bus = ieee_bus
        ieee_bus.attach(self)
        hear_atn
      end

      # The lines the drive pulls on the bus while ATN is low or not
      # (IEEEPort). They hold still while it sleeps, so reading them leaves
      # it asleep.
      def ieee_low_lines(atn) = @serial_port.ieee_low_lines(atn)

      private

      # One drive cycle, as the 1541's (Model1541#step): the mechanism, then
      # ATN on VIA 1's CA1, the VIAs and the CPU.
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
end
