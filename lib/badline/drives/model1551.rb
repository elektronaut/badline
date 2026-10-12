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
    # device 9.
    #
    # A 555 timer pulls IRQ low for about 7 µs every 8.3 ms, its R1 120K,
    # R2 100R and C1 0.1 µF, which runs the DOS's job loop. Nothing
    # acknowledges it: the line lets go on its own.
    class Model1551
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

      attr_reader :device, :cpu, :bus, :mechanism, :port, :tia, :cycles

      # The TIA in the computer's expansion port, and the cable to it.
      attr_reader :host_tia, :cable

      # The host's clock rate, which the drive's cycles keep pace with.
      attr_writer :host_clock_hz

      def model_name = "1551"

      # +rom+ covers $C000-$FFFF, and defaults to the DOS image in the ROM
      # path. +device+ is 8 or 9, as the jumper on the TIA's PC5 sets it.
      def initialize(rom: nil, host_clock_hz: CLOCK_HZ, device: 8, debug: false)
        raise ArgumentError, "a 1551 is device 8 or 9, not #{device}" unless [8, 9].include?(device)

        @device = device
        @mechanism = Model1541::Mechanism.new
        @mechanism.clock_hz = CLOCK_HZ
        @port = Port.new(@mechanism)
        @tia = TIA.new(@mechanism, device:)
        @host_tia = Chips::TIA.new
        @cable = Cable.new(@host_tia, @tia.chip)
        @bus = Bus.new(rom: rom || ROM.load("dos1551.rom", 0xc000), port: @port, tia: @tia)
        @cpu = CPU.new(@bus, debug:)
        @host_clock_hz = host_clock_hz
        @phase = 0
        @cycles = 0
        @irq_timer = IRQ_PERIOD
      end

      def ram = @bus.ram

      # Puts a Disk in the drive (Model1541::Disk.from_d64 makes one from an
      # image). Nil takes the disk out.
      def insert(disk)
        @mechanism.insert(disk)
      end

      # Puts in a Disk from the .d64 or .g64 image at +path+, write-protected
      # with `read_only`.
      def insert_image(path, read_only: false)
        insert(Model1541::Disk.open(path, read_only:))
      end

      def disk = @mechanism.disk

      # Whether the activity LED is lit.
      def led_on? = @mechanism.led_on?

      # The power LED, which stays lit.
      def power_led_on? = true

      # Stores what the head wrote since the motor last stopped in the
      # disk's image, as the motor stopping does.
      def flush
        @mechanism.flush
      end

      # The computer's RESET line reaches the interface's TIA and, through
      # the cable, the CPU, its port and the drive's TIA. RAM keeps its
      # contents, and the 555 runs on.
      def reset!
        @host_tia.reset!
        @port.reset!
        @tia.reset!
        @cpu.reset!
      end

      # Runs the drive cycles that fall in one host cycle, on the drive's own
      # crystal through a fractional accumulator.
      def host_cycle!
        phase = @phase + CLOCK_HZ
        host_clock_hz = @host_clock_hz
        while phase >= host_clock_hz
          step
          phase -= host_clock_hz
        end
        @phase = phase
      end

      # Runs one drive cycle.
      def cycle!
        step
      end

      def inspect
        "#<#{self.class.name} cycles=#{@cycles} cpu=(#{@cpu.inspect})>"
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
    end
  end
end
