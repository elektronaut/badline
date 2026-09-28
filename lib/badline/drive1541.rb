# frozen_string_literal: true

require "badline/drive1541/bus"
require "badline/drive1541/serial_port"

module Badline
  # The 1541 disk drive as a machine of its own: a 6502 running the DOS
  # ROM at 1 MHz, with 2 KB of RAM and two VIAs on its bus. VIA 1 faces
  # the serial bus and VIA 2 the disk mechanism.
  #
  # The drive runs on its own crystal, so it clocks against the host's
  # clock through a fractional accumulator: each host cycle adds 1 MHz
  # worth of phase, and every whole host period in it runs a drive cycle.
  # Against the PAL C64's 985,248 Hz that's one drive cycle per host cycle
  # and a second one about every 67. The host sets its clock on attaching
  # the drive, and until then the drive runs one cycle per host cycle.
  class Drive1541
    CLOCK_HZ = 1_000_000

    attr_reader :cpu, :bus, :via1, :via2, :cycles, :device, :serial_bus
    attr_writer :host_clock_hz

    def ram = @bus.ram

    # +rom+ covers $C000-$FFFF, and defaults to the DOS image in the ROM
    # path. +device+ is the number the jumpers on VIA 1's PB5 and PB6 set,
    # 8 to 11.
    def initialize(rom: nil, host_clock_hz: CLOCK_HZ, device: 8, debug: false)
      @device = device
      @serial_port = SerialPort.new(device:)
      @via1 = VIA.new(start: 0x1800, peripheral: @serial_port)
      @via2 = VIA.new(start: 0x1c00)
      @bus = Bus.new(rom: rom || ROM.load("dos1541.rom", 0xc000), via1: @via1, via2: @via2)
      @cpu = CPU.new(@bus, debug:)
      @host_clock_hz = host_clock_hz
      @phase = 0
      @cycles = 0
      @serial_bus = nil
      # CA1 powers up at the level of a released ATN, without an edge.
      @via1.ca1 = false
      @via1.reset!
      connect(IECBus.new)
    end

    # Plugs the drive into a serial bus, leaving the one it was on. A drive
    # starts out on a bus of its own, with nothing else on it.
    def connect(serial_bus)
      @serial_bus&.detach(self)
      @serial_bus = serial_bus
      @serial_port.bus = serial_bus
      serial_bus.attach(self)
      @via1.ca1 = serial_bus.atn_low?
    end

    # The serial bus's RESET line reaches the CPU and both VIAs. RAM keeps
    # its contents.
    def reset!
      @via1.reset!
      @via2.reset!
      @cpu.reset!
    end

    # Runs the drive cycles that fall in one host cycle: none, one or two.
    def host_cycle!
      phase = @phase + CLOCK_HZ
      while phase >= @host_clock_hz
        cycle!
        phase -= @host_clock_hz
      end
      @phase = phase
    end

    # One drive cycle. The VIAs clock ahead of the CPU, as the C64's chips
    # do, and either one pulls IRQ. Nothing drives NMI on the 1541. The CPU
    # runs whether or not the motor turns, since it answers ATN.
    #
    # ATN reaches VIA 1's CA1 through the same inverter as PB7, so CA1 goes
    # high as the C64 asserts ATN. Only the C64 drives ATN, and it runs
    # ahead of the drive in each host cycle, so sampling the line here
    # catches every change on the drive cycle it happens in.
    def cycle!
      @via1.ca1 = @serial_bus.atn_low?
      @via1.cycle!
      @via2.cycle!
      @cpu.irq = @via1.irq? || @via2.irq?
      @cpu.cycle!
      @cycles += 1
    end

    # The read electronics signal a whole GCR byte. BYTE READY reaches the
    # CPU's SO pin while VIA 2's CA2 (SOE) is high, which lets the DOS spin
    # on BVC for each byte.
    def byte_ready!
      @cpu.so! if @via2.ca2_output
    end

    def inspect
      "#<#{self.class.name} cycles=#{@cycles} cpu=(#{@cpu.inspect})>"
    end
  end
end
