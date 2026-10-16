# frozen_string_literal: true

require "badline/chips/tia"
require "badline/drives/model1541"
require "badline/drives/model1551/cpu"
require "badline/drives/model1551/port"
require "badline/drives/model1551/tia"
require "badline/drives/model1551/bus"
require "badline/drives/model1551/cable"
require "badline/drives/model1551/keyed_state"

module Badline
  module Drives
    # The 1551 disk drive of the 264 series: a 6510T at 2 MHz running DOS
    # 2.6 from 16 KB of ROM, with 2 KB of RAM, the 1541's GCR mechanism
    # behind a gate array, and a 6523 TIA facing the computer over TCBM, a
    # parallel cable to a second 6523 in the computer's expansion port
    # (Commodore schematic 251860; zimmers.net's 1551 memory map).
    #
    # The 6510T's port drives the mechanism as the 1541's VIA 2 port B does
    # and reads the write-protect sensor and the gate array's BYTE LATCHED
    # (Port). The TIA's port B reads the GCR byte the gate array latched and
    # drives the byte to write, and its port C selects reading or writing
    # and reads SYNC (TIA).
    #
    # The drive comes with its interface for the computer's expansion port,
    # a second 6523 (#host_tia), which the cable joins to the drive's
    # (Cable). The computer puts it at $FEE0 for device 8 and at $FEC0 for
    # device 9, as the drive's DEV line (PC2) says: high for device 8 and
    # low for device 9. The DOS sets DEV from the jumper at reset, and again
    # when a command renumbers the drive. The device number follows each
    # change on the line (#device).
    #
    # A 555 timer pulls IRQ low for about 7 µs every 8.3 ms, its R1 120K,
    # R2 100R and C1 0.1 µF, which runs the DOS's job loop. Nothing
    # acknowledges it: the line lets go on its own.
    #
    # Drives::Engine::Core clocks it against the host and sleeps through
    # the DOS's idle loop, which counts its passes in $61 (Engine::Idle's
    # pass counter), until the 555 is due to pull IRQ, the count wraps or
    # the computer moves the cable's lines.
    class Model1551
      include Engine::Core

      CLOCK_HZ = 2_000_000

      # The 555's cycle in drive cycles: high for 0.693 (R1 + R2) C and low,
      # pulling IRQ, for 0.693 R2 C.
      IRQ_PERIOD = 16_660
      IRQ_LOW = 14

      # The host cycles, at about 1 MHz, by which a 1551 switched on with the
      # machine has run its DOS's reset, the RAM test and the ROM checksum,
      # and answers TCBM: half a second, with a margin.
      BOOT_CYCLES = 600_000

      # Where the DOS's idle loop starts over, polling the TIA's port A for
      # a command from the computer.
      IDLE_LOOP = 0xeabd

      # The byte the idle loop increments on each pass.
      PASS_COUNTER = 0x61

      def port
        settle!
        @port
      end

      def tia
        settle!
        @tia
      end

      # The TIA in the computer's expansion port, which the computer reads
      # and writes without waking the drive.
      attr_reader :host_tia

      # The cable between the two TIAs.
      def cable
        settle!
        @cable
      end

      def model_name = "1551"

      # +rom+ covers $C000-$FFFF, and defaults to the DOS image in the ROM
      # path. +device+ is 8 or 9, as the jumper on the TIA's PC5 sets it.
      def initialize(rom: nil, host_clock_hz: CLOCK_HZ, device: 8, debug: false)
        raise ArgumentError, "a 1551 is device 8 or 9, not #{device}" unless [8, 9].include?(device)

        @device = device
        @clock_hz = CLOCK_HZ
        @mechanism = Model1541::Mechanism.new
        @mechanism.clock_hz = CLOCK_HZ
        @port = Port.new(@mechanism)
        @tia = TIA.new(@mechanism, device:)
        @host_tia = Chips::TIA.new
        @bus = Bus.new(rom: rom || ROM.load("dos1551.rom", 0xc000), port: @port, tia: @tia)
        @cpu = CPU.new(@bus, debug:)
        @idle_loop = IDLE_LOOP
        @host_clock_hz = host_clock_hz
        @phase = 0
        @cycles = 0
        @irq_timer = IRQ_PERIOD
        init_idle(debug)
        @pass_counter = PASS_COUNTER
        @dev_high = true
        @on_renumber = nil
        @cable = Cable.new(@host_tia, @tia.chip, self)
        @serial_port = @cable
      end

      # Calls the block with the old device number each time the DEV line
      # moves the drive to the other one.
      def on_renumber(&block)
        @on_renumber = block
      end

      # The cable's DEV line, high or not. A change moves the drive to
      # device 8 while it's high, and to device 9 while it's low.
      def dev_line(high)
        return if high == @dev_high

        @dev_high = high
        old = @device
        @device = high ? 8 : 9
        @on_renumber&.call(old) unless @device == old
      end

      # Puts in a Disk from the .d64 or .g64 image at +path+, write-protected
      # with `read_only`.
      def insert_image(path, read_only: false)
        insert(Model1541::Disk.open(path, read_only:))
      end

      # The computer's RESET line reaches the interface's TIA and, through
      # the cable, the CPU, its port and the drive's TIA. RAM keeps its
      # contents, and the 555 runs on.
      def reset!
        settle!
        @host_tia.reset!
        @port.reset!
        @tia.reset!
        @cpu.reset!
      end

      private

      # One drive cycle: the mechanism turns the disk ahead of the CPU, and
      # the 555 pulls IRQ while its output is low.
      def step
        @mechanism.cycle!
        timer = @irq_timer - 1
        timer = IRQ_PERIOD if timer.zero?
        @irq_timer = timer
        @cpu.irq = timer <= IRQ_LOW
        @cpu.cycle!
        @cycles += 1
      end

      # A pass of the idle loop reads the TIA's port A, which holds still
      # until the computer moves the cable's lines, and RAM. It repeats
      # while the motor is off and the 555 leaves IRQ alone, for as long as
      # the 555 leaves room (see Engine::Idle).
      def busy_for_pass? = @mechanism.motor_on? || @irq_timer <= IRQ_LOW

      def quiet_cycles
        quiet = @irq_timer - IRQ_LOW - 1
        quiet.negative? ? 0 : quiet
      end

      def idle_state
        chip = @tia.chip
        [*@cpu.counting_state, @bus.data, *@mechanism.idle_state, *chip.ports, *chip.directions, *chip.inputs,
         @port.ddr, @port.data]
      end

      def fast_forward_chips(cycles)
        @irq_timer -= cycles
      end

      # Every 555 pulse runs the job loop, which reads the port and the TIA,
      # so no orbit (Engine::Orbit) comes round, and the drive keeps no
      # anchors.
      def anchor = nil

      def counter_state(_touched) = []

      def skip_chip_orbits(_cycles, _touched) = nil
    end
  end
end
