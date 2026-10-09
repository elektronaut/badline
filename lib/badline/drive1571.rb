# frozen_string_literal: true

require "badline/drive1571/cpu"
require "badline/drive1571/wd1770"
require "badline/drive1571/serial_port"
require "badline/drive1571/serial_via"
require "badline/drive1571/bus"

module Badline
  # The 1571 disk drive, the C128D's built-in one: the 1541's 6502, two
  # VIAs and GCR mechanism, with a second head, a 6526 CIA for fast
  # serial, a WD1770 for MFM disks and DOS 3.0 in 32 KB of ROM. Drive::Core
  # clocks it against the host and sleeps through the DOS's idle loop.
  #
  # VIA 1's port A picks the clock, 1 or 2 MHz on PA5, and the head on
  # PA2, and reads the track 0 sensor and BYTE READY (SerialPort). The
  # DOS resets at 2 MHz and drops to 1 MHz as a 1541 would run, which is
  # how it stays until a C128 asks for fast serial. The disk turns at the
  # same speed either way (Drive1541::Mechanism#clock_hz=).
  #
  # The CIA sits at $4000, on the IRQ line with both VIAs. Only its serial
  # port is wired: through buffers PA1 turns round, its CNT drives SRQ and
  # its SP DATA, or it hears them. The drive pushes its pins into the bus
  # as they move, and hears the host's as the host pushes them, pin by
  # pin, so each byte goes through both shift registers bit by bit. The
  # CIA takes no part in a pass of the idle loop: the drive sleeps only
  # while the CIA is quiet (CIA#quiet?), and any access to it, or the
  # host moving its fast serial pins, wakes the drive.
  class Drive1571
    include Drive::Core

    CLOCK_HZ = 1_000_000
    FAST_CLOCK_HZ = 2_000_000

    # Where the DOS 3.0 idle loop starts over, as DOS 2.6's does.
    IDLE_LOOP = 0xebff

    # VIA 1's port A outputs.
    FAST_SERIAL_OUT = 0x02
    SIDE = 0x04
    FAST = 0x20

    # Whether PA1 turns the fast serial buffers outwards, the drive's CIA
    # driving DATA and SRQ.
    attr_reader :fast_serial_out

    def cia
      settle!
      @cia
    end

    def fdc
      settle!
      @fdc
    end

    def model_name = "1571"

    # +rom+ covers $8000-$FFFF, and defaults to the DOS image in the ROM
    # path. +device+ is the number the jumpers on VIA 1's PB5 and PB6 set,
    # 8 to 11.
    def initialize(rom: nil, host_clock_hz: CLOCK_HZ, device: 8, debug: false)
      @device = device
      @clock_hz = CLOCK_HZ
      @fast_serial_out = false
      @fast_output = 0
      @mechanism = Drive1541::Mechanism.new(slip: 2)
      @serial_port = SerialPort.new(@mechanism, device:)
      @via1 = SerialVIA.new(start: 0x1800, peripheral: @serial_port, drive: self)
      @via2 = Drive1541::DiskVIA.new(start: 0x1c00, mechanism: @mechanism)
      @cia = CIA.new(start: 0x4000)
      @fdc = WD1770.new
      @bus = Bus.new(rom: rom || ROM.load("dos1571.rom", 0x8000), via1: @via1, via2: @via2, cia: @cia, fdc: @fdc)
      @cpu = CPU.new(@bus, debug:)
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

    # The serial bus's RESET line reaches the CPU, both VIAs and the CIA.
    # RAM keeps its contents.
    def reset!
      settle!
      @via1.reset!
      @via2.reset!
      @cia.reset!
      @cpu.reset!
    end

    # VIA 1 drives port A to +lines+: the side, the clock rate and the fast
    # serial direction follow it.
    def port_a_written(lines)
      @mechanism.side = lines.anybits?(SIDE) ? 1 : 0
      fast_serial_out = lines.anybits?(FAST_SERIAL_OUT)
      turn_fast_serial(fast_serial_out) if fast_serial_out != @fast_serial_out
      clock_hz = lines.anybits?(FAST) ? FAST_CLOCK_HZ : CLOCK_HZ
      return if clock_hz == @clock_hz

      @clock_hz = clock_hz
      @mechanism.clock_hz = clock_hz
    end

    # Whether the drive runs at 2 MHz.
    def fast? = @clock_hz == FAST_CLOCK_HZ

    # VIA 1's port B, with the fast serial pins pulling DATA and SRQ
    # (IECBus::DRIVE_FAST_DATA and DRIVE_FAST_SRQ) above it.
    def serial_output = @via1.port_b_output | @fast_output

    # The host moved its fast serial pins: the CIA hears SRQ on CNT and
    # DATA on SP while PA1 turns the buffers inwards.
    def fast_lines_moved
      settle!
      hear_fast_serial unless @fast_serial_out
    end

    # The drive's whole state, as the 1541's (Drive1541#save_state), with
    # the CIA and the WD1770's registers. The clock rate, the side and the
    # fast serial direction follow from VIA 1's port A.
    def save_state(out)
      settle!
      out.marker("DRIVE1571")
      out.int(@phase).int(@cycles).boolean(@mechanism.so_pending)
      @serial_port.save_state(out)
      @via1.save_state(out)
      @via2.save_state(out)
      @cia.save_state(out)
      @fdc.save_state(out)
      @bus.save_state(out)
      @cpu.save_state(out)
      @mechanism.save_state(out)
    end

    def load_state(input)
      settle!
      input.marker("DRIVE1571")
      @phase = input.int
      @cycles = input.int
      @mechanism.so_pending = input.boolean?
      @serial_port.load_state(input)
      @via1.load_state(input)
      @via2.load_state(input)
      @cia.load_state(input)
      @fdc.load_state(input)
      @bus.load_state(input)
      @cpu.load_state(input)
      @mechanism.load_state(input)
      @fast_serial_out = @via1.port_a_output.anybits?(FAST_SERIAL_OUT)
      port_a_written(@via1.port_a_output)
      push_fast_output(@fast_serial_out ? fast_pins : 0)
      forget_orbits
    end

    private

    # One drive cycle, as the 1541's (Drive1541#step), with the CIA
    # clocked beside the VIAs and pulling IRQ with them.
    def step
      so = @mechanism.take_so
      @mechanism.cycle!
      @via1.ca1 = @serial_port.atn_low?
      @via1.cycle!
      @via2.cycle!
      @cia.cycle!
      drive_fast_serial if @fast_serial_out
      @cpu.irq = @via1.irq? || @via2.irq? || @cia.interrupted?
      @cpu.so! if so
      @cpu.cycle!
      @cycles += 1
    end

    # The VIAs' quiet cycles while the CIA is quiet, and none otherwise.
    def quiet_cycles
      @cia.quiet? ? [@via1.quiet_cycles, @via2.quiet_cycles].min : 0
    end

    def fast_forward_chips(cycles)
      @cia.fast_forward(cycles)
    end

    # PA1 turned the buffers round: outwards the CIA's pins drive the
    # lines, and inwards they let go and hear them.
    def turn_fast_serial(out)
      @fast_serial_out = out
      return unless @serial_bus

      push_fast_output(out ? fast_pins : 0)
      hear_fast_serial unless out
    end

    def drive_fast_serial
      low = fast_pins
      push_fast_output(low) if low != @fast_output
    end

    # The lines the CIA's CNT and SP pull while its serial port drives
    # them.
    def fast_pins
      serial = @cia.serial
      return 0 unless serial.output?

      low = serial.cnt ? 0 : IECBus::DRIVE_FAST_SRQ
      serial.sp_out ? low : low | IECBus::DRIVE_FAST_DATA
    end

    def push_fast_output(low)
      @fast_output = low
      @serial_bus&.drives_fast_moved!
    end

    def hear_fast_serial
      low = @serial_bus.low_lines
      serial = @cia.serial
      serial.cnt_in = low.nobits?(IECBus::SRQ)
      serial.sp_in = low.nobits?(IECBus::DATA)
    end
  end
end
