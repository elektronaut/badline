# frozen_string_literal: true

require "badline/drive"
require "badline/drive1581/track"
require "badline/drive1581/track_bytes"
require "badline/drive1581/disk"
require "badline/drive1581/mechanism"
require "badline/drive1581/wd1772"
require "badline/drive1581/cpu"
require "badline/drive1581/serial_port"
require "badline/drive1581/bus"

module Badline
  # The 1581 3.5" disk drive: a 6502 at 2 MHz with 8 KB of RAM, an 8520
  # for the serial bus and the mechanism's lines, a WD1772 for the MFM
  # disk, and the DOS in 32 KB of ROM (1581 Service Manual). Drive::Core
  # clocks it against the host.
  #
  # The 8520's port B faces the serial bus as VIA 1's does on the 1541,
  # with the same bits, and ATN reaches its FLAG pin, so ATN going low
  # interrupts the DOS. Its SP and CNT carry fast serial on DATA and SRQ,
  # through buffers PB5 turns round (Drive::FastSerial), as the 1571's
  # 6526 does. The ATN acknowledge differs: a NAND of ATN IN and
  # ATN ACK pulls DATA, so DATA follows ATN only while ATN is asserted
  # and PB4 is high, where the 1541's XOR pulls it whenever the two
  # differ (IECBus::DRIVE_ATN_GATED). Port A drives the motor, the side
  # and the two LEDs, and reads the switches and the mechanism's /RDY and
  # /DISK CHNG (SerialPort). Timer B interrupts every 10 ms for the
  # controller code that runs the WD1772.
  #
  # The 8520 differs from the 6526 in its TOD, a 24-bit binary event
  # counter where the 6526 keeps a BCD clock. The 1581 holds the TOD pin
  # high when it carries a WD1772 (jumper J1 out), so the counter never
  # counts, and the DOS's one use of it, writing $00 to the low byte and
  # reading it back 20 µs later to tell a WD1770 from a WD1772, reads $00
  # on either chip: the drive's CIA gets no TOD pulses (CIA's tod_hz).
  class Drive1581
    include Drive::Core
    include Drive::FastSerial

    CLOCK_HZ = 2_000_000

    # Where the DOS's idle loop starts over (see Drive::Idle).
    IDLE_LOOP = 0xb105

    # The host cycles, at about 1 MHz, by which a 1581 switched on with the
    # machine has run its DOS's reset, the RAM test, the ROM checksum and
    # the controller's half-second wait, and waits on the bus: 2.32 s,
    # with a margin.
    BOOT_CYCLES = 2_700_000

    # The 8520's port A outputs.
    SIDE = 0x01
    MOTOR = 0x04
    POWER_LED = 0x20
    ACTIVITY_LED = 0x40

    # Port B's ATN acknowledge, and the fast serial direction.
    ATN_ACK = 0x10
    FAST_SERIAL_OUT = 0x20

    def cia
      settle!
      @cia
    end

    def fdc
      settle!
      @fdc
    end

    def model_name = "1581"

    # +rom+ covers $8000-$FFFF, and defaults to the DOS image in the ROM
    # path. +device+ is the number the switches on port A's PA3 and PA4
    # set, 8 to 11.
    def initialize(rom: nil, host_clock_hz: Drive1541::CLOCK_HZ, device: 8, debug: false)
      @device = device
      @clock_hz = CLOCK_HZ
      @mechanism = Mechanism.new
      @fdc = WD1772.new(@mechanism)
      @serial_port = SerialPort.new(@mechanism, device:)
      @cia = CIA.new(start: 0x4000, peripheral: @serial_port, tod_hz: 0)
      @bus = Bus.new(rom: rom || ROM.load("dos1581.rom", 0x8000), cia: @cia, fdc: @fdc, drive: self)
      @cpu = CPU.new(@bus, debug:)
      @idle_loop = IDLE_LOOP
      @host_clock_hz = host_clock_hz
      @phase = 0
      @cycles = 0
      @serial_bus = nil
      @atn = false
      @activity = false
      @power = false
      init_fast_serial
      init_idle(debug)
      ports_written
      connect(IECBus.new)
    end

    # The serial bus's RESET line reaches the CPU, the 8520 and the
    # WD1772. RAM keeps its contents.
    def reset!
      settle!
      @cia.reset!
      @fdc.reset!
      ports_written
      @cpu.reset!
    end

    def insert(disk)
      settle!
      @mechanism.insert(disk, @fdc.now)
      @fdc.spin_changed
    end

    # Puts in a Disk from the .d81 image at +path+, write-protected with
    # `read_only`.
    def insert_image(path, read_only: false)
      insert(Disk.open(path, read_only:))
    end

    # Whether the activity LED is lit. The power LED stays lit, and
    # flashes on an error.
    def led_on? = @activity

    def power_led_on? = @power

    # The 8520's port B as it drives the serial bus, in VIA 1's bits, the
    # ATN acknowledge turned round for the NAND that gates it, with the
    # fast serial pins above it. It holds still while the drive sleeps, so
    # reading it leaves the drive asleep.
    def serial_output
      lines = @cia.port_b_lines
      output = (lines & (IECBus::DRIVE_DATA_OUT | IECBus::DRIVE_CLK_OUT)) | IECBus::DRIVE_ATN_GATED | @fast_output
      lines.anybits?(ATN_ACK) ? output : output | IECBus::DRIVE_ATNA
    end

    # The 8520's ports drive the motor, the side, the LEDs and the fast
    # serial buffers: the drive follows them after every write to a port
    # or direction register.
    def ports_written
      fast_serial_out = @cia.port_b_lines.anybits?(FAST_SERIAL_OUT)
      turn_fast_serial(fast_serial_out) if fast_serial_out != @fast_serial_out
      lines = @cia.port_a_lines
      @mechanism.side = lines.anybits?(SIDE) ? 1 : 0
      @activity = lines.anybits?(ACTIVITY_LED)
      @power = lines.anybits?(POWER_LED)
      motor = lines.nobits?(MOTOR)
      return if motor == @mechanism.motor_on?

      @mechanism.motor(motor, @fdc.now)
      @fdc.spin_changed
    end

    # The drive's whole state, as the 1541's (Drive1541#save_state), with
    # the 8520 and the WD1772 in place of the VIAs.
    def save_state(out)
      settle!
      out.marker("DRIVE1581")
      out.int(@phase).int(@cycles).boolean(@atn)
      @serial_port.save_state(out)
      @cia.save_state(out)
      @fdc.save_state(out)
      @bus.save_state(out)
      @cpu.save_state(out)
      @mechanism.save_state(out)
    end

    def load_state(input)
      settle!
      input.marker("DRIVE1581")
      @phase = input.int
      @cycles = input.int
      @atn = input.boolean?
      @serial_port.load_state(input)
      @cia.load_state(input)
      @fdc.load_state(input)
      @bus.load_state(input)
      @cpu.load_state(input)
      @mechanism.load_state(input)
      @fast_serial_out = @cia.port_b_lines.anybits?(FAST_SERIAL_OUT)
      ports_written
      push_fast_output(@fast_serial_out ? fast_pins : 0)
      forget_orbits
    end

    private

    # One drive cycle: ATN going low pulls FLAG, the WD1772 and the 8520
    # clock ahead of the CPU, and the 8520 alone pulls IRQ.
    def step
      atn = @serial_port.atn_low?
      if atn != @atn
        @atn = atn
        @cia.flag! if atn
      end
      @fdc.cycle!
      @cia.cycle!
      drive_fast_serial if @fast_serial_out
      @cpu.irq = @cia.interrupted?
      @cpu.cycle!
      @cycles += 1
    end

    def hear_atn
      @atn = @serial_port.atn_low?
    end

    # A pass of the idle loop reads and writes RAM alone, so it repeats
    # while the 8520 pulls no IRQ, for as long as the 8520's counters and
    # the WD1772's next phase leave room: until timer B's next interrupt
    # for the controller code. Neither chip changes but by the clock, so
    # only the CPU is compared.
    def busy_for_pass? = @cia.interrupted?

    def quiet_cycles = [@cia.quiet_cycles, @fdc.quiet_cycles].min

    def idle_state = [*@cpu.idle_state, @bus.data, @atn]

    def fast_forward_chips(cycles)
      @cia.fast_forward(cycles)
      @fdc.fast_forward(cycles)
    end

    # Every timer B interrupt reads the 8520, so no orbit (Drive::Orbit)
    # comes round, and the drive keeps no anchors.
    def anchor = nil

    def counter_state(_touched) = []

    def skip_chip_orbits(_cycles, _touched) = nil
  end
end
