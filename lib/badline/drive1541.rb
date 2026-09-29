# frozen_string_literal: true

require "badline/drive1541/bus"
require "badline/drive1541/serial_port"
require "badline/drive1541/gcr"
require "badline/drive1541/track"
require "badline/drive1541/disk"
require "badline/drive1541/mechanism"
require "badline/drive1541/disk_via"
require "badline/drive1541/sleep"
require "badline/drive1541/idle"
require "badline/drive1541/orbit"

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
  #
  # VIA 2's port B runs the Mechanism, which reads a Disk put in with
  # insert.
  #
  # While the DOS idles, host_cycle! skips the drive's cycles and catches
  # up on them later, exactly (see Idle). The readers of the drive's parts
  # catch up first, so they find the drive as running every cycle would
  # have left it. Once the DOS's timer interrupts come round, the drive
  # sleeps through them too (see Orbit).
  class Drive1541
    include Sleep
    include Idle
    include Orbit

    CLOCK_HZ = 1_000_000

    attr_reader :device, :serial_bus

    def cpu
      settle!
      @cpu
    end

    def bus
      settle!
      @bus
    end

    def via1
      settle!
      @via1
    end

    def via2
      settle!
      @via2
    end

    def mechanism
      settle!
      @mechanism
    end

    def cycles
      settle!
      @cycles
    end

    def ram = bus.ram

    def host_clock_hz=(clock_hz)
      settle!
      @host_clock_hz = clock_hz
    end

    # +rom+ covers $C000-$FFFF, and defaults to the DOS image in the ROM
    # path. +device+ is the number the jumpers on VIA 1's PB5 and PB6 set,
    # 8 to 11.
    def initialize(rom: nil, host_clock_hz: CLOCK_HZ, device: 8, debug: false)
      @device = device
      @serial_port = SerialPort.new(device:)
      @via1 = VIA.new(start: 0x1800, peripheral: @serial_port)
      @mechanism = Mechanism.new(self)
      @via2 = DiskVIA.new(start: 0x1c00, mechanism: @mechanism)
      @bus = Bus.new(rom: rom || ROM.load("dos1541.rom", 0xc000), via1: @via1, via2: @via2)
      @cpu = CPU.new(@bus, debug:)
      @host_clock_hz = host_clock_hz
      @phase = 0
      @cycles = 0
      @so_pending = false
      @serial_bus = nil
      init_idle(debug)
      # CA1 powers up at the level of a released ATN, without an edge.
      @via1.ca1 = false
      @via1.reset!
      connect(IECBus.new)
    end

    # Plugs the drive into a serial bus, leaving the one it was on. A drive
    # starts out on a bus of its own, with nothing else on it.
    def connect(serial_bus)
      settle!
      @serial_bus&.detach(self)
      @serial_bus = serial_bus
      @serial_port.bus = serial_bus
      serial_bus.attach(self)
      @via1.ca1 = @serial_port.atn_low?
    end

    # Puts a Disk in the drive (Disk.from_d64 makes one from an image).
    # Nil takes the disk out.
    def insert(disk)
      settle!
      @mechanism.insert(disk)
    end

    def disk = mechanism.disk

    # Whether the LED is lit. Reading it leaves the drive asleep: the LED
    # is the same at the end of every pass the drive sleeps through.
    def led_on? = @mechanism.led_on?

    # VIA 1's port B as it drives the serial bus. It holds still while the
    # drive sleeps, so reading it leaves the drive asleep.
    def serial_output = @via1.port_b_output

    # Stores what the head wrote since the motor last stopped in the
    # disk's image, as the motor stopping does.
    def flush
      settle!
      @mechanism.flush
    end

    # The serial bus's RESET line reaches the CPU and both VIAs. RAM keeps
    # its contents.
    def reset!
      settle!
      @via1.reset!
      @via2.reset!
      @cpu.reset!
    end

    # Runs the drive cycles that fall in one host cycle: none, one or two.
    # The host has run this cycle already, and the drive sees what it did
    # from the next one on (see SerialPort). Asleep, the drive owes the
    # cycles instead, until ATN moves or its counters are due (see Idle).
    # It looks at ATN only after the C64 wrote CIA 2's port A, on a bus
    # that says so (see host_written!).
    def host_cycle!
      if @asleep
        return if (@slept += 1) != @wake_at && @host_still

        return doze
      end

      phase = @phase + CLOCK_HZ
      while phase >= @host_clock_hz
        @asleep ? @owed += 1 : run_cycle
        phase -= @host_clock_hz
      end
      @phase = phase
      settle! if @serial_port.atn_moved?
      @serial_port.latch_host
      plan_wake if @asleep
    end

    # The C64 wrote CIA 2's port A, so ATN may have moved.
    def host_written!
      @host_still = false
    end

    # Runs one drive cycle, catching up first on any the drive owes (see
    # step).
    def cycle!
      settle!
      step
    end

    def inspect
      "#<#{self.class.name} cycles=#{cycles} cpu=(#{cpu.inspect})>"
    end

    # The read electronics signal a whole GCR byte. BYTE READY pulls VIA 2's
    # CA1 low, a falling edge that sets its flag and, with latching on,
    # latches port A. It reaches the CPU's SO pin while VIA 2's CA2 (SOE)
    # is high, which lets the DOS spin on BVC for each byte. The CPU
    # samples SO on the next cycle (see step).
    def byte_ready!
      @via2.ca1 = false
      @so_pending = true if @via2.ca2_output
    end

    # BYTE READY lets go of CA1 with the next bit.
    def byte_ready_ended!
      @via2.ca1 = true
    end

    private

    # A drive cycle from host_cycle!, which may find the idle loop.
    def run_cycle
      step
      idle_loop_reached if @cpu.program_counter == IDLE_LOOP && @idle_skip
    end

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
      so = @so_pending
      @so_pending = false
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
