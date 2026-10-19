# frozen_string_literal: true

require "badline/chips/riot"
require "badline/chips/rriot"
require "badline/drives/ieee_bus"
require "badline/drives/engine"
require "badline/drives/model8050/ip_bus"
require "badline/drives/model8050/fdc_bus"
require "badline/drives/model8050/parts"
require "badline/drives/model8050/ieee_port"
require "badline/drives/model8050/disk"
require "badline/drives/model8050/mechanism"
require "badline/drives/model8050/idle"
require "badline/drives/model8050/keyed_state"

module Badline
  module Drives
    # The 8050 dual disk drive of the PET and CBM-II, two drives on one
    # IEEE-488 unit (schematic 8050001; the 8050/8250 service manual).
    #
    # Two 6502s share the board, clocked at 1 MHz from one 12 MHz crystal
    # on opposite phases. The interface processor (IP) runs DOS 2.7 from
    # 16 KB of ROM at $C000, with two 6532s (IPBus): their RAM is its zero
    # page and stack, and their ports face the IEEE-488 bus (IEEEPort). The
    # floppy controller (FDC) runs the 1 KB program in its 6530's ROM, with
    # a VIA and the 6530 facing the drives (FDCBus, Mechanism). The two
    # meet in 4 KB of common RAM, which each reaches in its own half of
    # the cycle: the IP leaves jobs there, and the FDC runs them.
    #
    # Reset starts both. The FDC waits on the common RAM for the IP, which
    # tests it, copies the FDC's start-up code into it ($C370) and waits for
    # the FDC to answer, before both settle into their idle loops.
    #
    # The drive clocks against the host through a phase accumulator, as
    # Drives::Engine::Core does: each host cycle adds 1 MHz of phase, and
    # every whole host period in it runs a cycle of both processors. While
    # both processors idle, it sleeps instead (Idle), and the readers of its
    # parts catch it up first.
    class Model8050
      include Idle

      CLOCK_HZ = 1_000_000

      # The host cycles by which a unit switched on with the machine has
      # run the IP's RAM test and the FDC's start-up and reads its jumpers.
      BOOT_CYCLES = 1_500_000

      attr_reader :device, :ieee_bus

      def ip_cpu = settled(@ip_cpu)

      def fdc_cpu = settled(@fdc_cpu)

      def ip_bus = settled(@ip_bus)

      def fdc_bus = settled(@fdc_bus)

      def common = settled(@common)

      def data_riot = settled(@data_riot)

      def control_riot = settled(@control_riot)

      def via = settled(@via)

      def rriot = settled(@rriot)

      def mechanism = settled(@mechanism)

      def cycles
        settle!
        @cycles
      end

      attr_writer :host_clock_hz

      def model_name = "8050"

      def boot_cycles = BOOT_CYCLES

      # Whether the unit is where VICE saves it: both processors between
      # instructions, the FDC at the start of its idle loop.
      def settled_for_vice?
        fdc = fdc_cpu
        ip_cpu.boundary? && fdc.boundary? && fdc.program_counter == Idle::FDC_LOOP
      end

      # The sides each drive's disk has.
      def sides = 1

      # +dos_rom+ covers $C000-$FFFF and +fdc_rom+ is the 6530's mask, each
      # defaulting to the image in the ROM path: DOS 2.7 and the mask for
      # MPI mechanisms. +device+ is the number the jumpers set, 8 to 15.
      def initialize(dos_rom: nil, fdc_rom: nil, host_clock_hz: CLOCK_HZ, device: 8)
        @device = device
        @host_clock_hz = host_clock_hz
        @phase = 0
        @cycles = 0
        build_ip(dos_rom || ROM.load("8050/dos-2.7.rom", 0xc000))
        build_fdc(fdc_rom || ROM.read("8050/fdc-901869-01.rom"))
        @ip_cpu = IPCPU.new(@ip_bus)
        @fdc_cpu = FDCCPU.new(@fdc_bus)
        init_idle
        @ieee_bus.attach(self)
      end

      # Plugs the unit into an IEEE-488 bus, leaving the one it was on.
      def connect(ieee_bus)
        settle!
        @ieee_bus.detach(self)
        @ieee_bus = ieee_bus
        @ieee_port.bus = ieee_bus
        ieee_bus.attach(self)
      end

      # The lines the unit pulls on the bus while ATN is low or not
      # (IEEEPort).
      def ieee_low_lines(atn) = @ieee_port.ieee_low_lines(atn)

      # The controller pushed its lines into the bus.
      def host_written! = nil

      # Which LEDs are lit: bit 0 drive 1's, bit 1 drive 0's, bit 2 the
      # error LED. They hold still while the unit sleeps, so reading them
      # leaves it asleep.
      def leds = @ieee_port.leds

      def led_on? = leds.anybits?(0x03)

      # Puts a Disk in +drive+, 0 or 1. Nil takes the disk out.
      def insert(disk, drive: 0)
        settle!
        @mechanism.insert(disk, drive)
      end

      # Puts in the .d80 or .d82 image at +path+, write-protected with
      # `read_only`.
      def insert_image(path, drive: 0, read_only: false)
        image_class = File.extname(path).casecmp?(".d82") ? Storage::D82Image : Storage::D80Image
        insert(Disk.new(image_class.new(path, read_only:)), drive:)
      end

      # The Disk in +drive+, or nil.
      def disk(drive = 0) = @mechanism.disk(drive)

      # Stores what the heads wrote in the disks' images, as the motors
      # stopping do.
      def flush
        settle!
        @mechanism.flush
      end

      def power_led_on? = true

      # Runs the drive cycles that fall in one host cycle, then takes the
      # controller's lines for the next. Asleep, the unit owes the cycles
      # instead, and wakes once the controller has moved a line.
      def host_cycle!
        phase = @phase + CLOCK_HZ
        while phase >= @host_clock_hz
          @asleep ? owe_cycle : run_cycle
          phase -= @host_clock_hz
        end
        @phase = phase
        settle! if @asleep && @ieee_port.lines_moved?
        @ieee_port.latch_host
      end

      def cycle!
        settle!
        run_cycle
      end

      # The bus's IFC line resets both processors and every chip. RAM keeps
      # its contents.
      def reset!
        settle!
        @data_riot.reset!
        @control_riot.reset!
        @via.reset!
        @rriot.reset!
        @ip_cpu.reset!
        @fdc_cpu.reset!
      end

      def inspect
        "#<#{self.class.name} cycles=#{@cycles} ip=(#{@ip_cpu.inspect}) fdc=(#{@fdc_cpu.inspect})>"
      end

      private

      def settled(part)
        settle!
        part
      end

      def run_cycle
        step
        watch_loops if @idle_skip
      end

      def build_ip(rom)
        @common = Memory.new([], length: 0x1000)
        @ieee_bus = IEEEBus.new
        @ieee_port = IEEEPort.new(device: @device, bus: @ieee_bus)
        @data_riot = DataRIOT.new(peripheral: DataLines.new(@ieee_port))
        @control_riot = ControlRIOT.new(peripheral: ControlLines.new(@ieee_port))
        @ieee_port.data_riot = @data_riot
        @ieee_port.control_riot = @control_riot
        @ip_bus = IPBus.new(rom:, common: @common, data_riot: @data_riot, control_riot: @control_riot)
      end

      def build_fdc(rom)
        @mechanism = Mechanism.new(sides:)
        @via = ControllerVIA.new(start: 0x0040, peripheral: ReadLines.new(@mechanism))
        @rriot = ControllerRRIOT.new(rom:, peripheral: StatusLines.new(@mechanism))
        @fdc_bus = FDCBus.new(common: @common, via: @via, rriot: @rriot)
        @mechanism.via = @via
        @mechanism.rriot = @rriot
      end

      # One cycle of the board: the drives, then the chips, then the IP and
      # the FDC, each in its own half of the cycle. ATN reaches UE1's PA7 as
      # the port latched it. UE1 pulls the IP's IRQ, and the VIA and the
      # 6530 the FDC's. Byte ready sets the FDC's V flag through SO for the
      # next cycle's instruction step, as on the 1541.
      def step
        so = @mechanism.take_so
        @mechanism.cycle!
        @control_riot.pa7 = @ieee_port.atn_low?
        @data_riot.cycle!
        @control_riot.cycle!
        @via.cycle!
        @rriot.cycle!
        @ip_cpu.irq = @control_riot.irq?
        @ip_cpu.cycle!
        @fdc_cpu.irq = @via.irq? || @rriot.irq?
        @fdc_cpu.so! if so
        @fdc_cpu.cycle!
        @cycles += 1
      end
    end

    # The 8250: the 8050's board driving double-sided mechanisms, 154 tracks
    # a disk, with jumper E3 grounding the 6530's PB6 to say so.
    class Model8250 < Model8050
      def model_name = "8250"

      def sides = 2
    end
  end
end
