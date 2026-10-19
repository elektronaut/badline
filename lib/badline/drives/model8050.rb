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
require "badline/drives/model8050/dos_board"
require "badline/drives/model8050/board"
require "badline/drives/model8050/idle"
require "badline/drives/model8050/keyed_state"

module Badline
  module Drives
    # The 8050 dual disk drive of the PET and CBM-II, two drives on one
    # IEEE-488 unit (schematic 8050001; the 8050/8250 service manual).
    #
    # Two 6502s share the board (Board), clocked at 1 MHz from one 12 MHz
    # crystal on opposite phases. The interface processor (IP) runs DOS 2.7
    # from 16 KB of ROM at $C000, with two 6532s (IPBus): their RAM is its
    # zero page and stack, and their ports face the IEEE-488 bus
    # (IEEEPort). The floppy controller (FDC) runs the 1 KB program in its
    # 6530's ROM, with a VIA and the 6530 facing the drives (FDCBus,
    # Mechanism). The two meet in 4 KB of common RAM, which each reaches in
    # its own half of the cycle: the IP leaves jobs there, and the FDC runs
    # them.
    #
    # Reset starts both. The FDC waits on the common RAM for the IP, which
    # tests it, copies the FDC's start-up code into it ($C370) and waits for
    # the FDC to answer, before both settle into their idle loops.
    class Model8050
      include Board
      include Idle

      CLOCK_HZ = 1_000_000

      # The host cycles by which a unit switched on with the machine has
      # run the IP's RAM test and the FDC's start-up and reads its jumpers.
      BOOT_CYCLES = 1_500_000

      def model_name = "8050"

      def boot_cycles = BOOT_CYCLES

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
        init_idle(Idle::IP_LOOP, Idle::FDC_LOOP)
        @ieee_bus.attach(self)
      end

      # Puts in the .d80 or .d82 image at +path+, write-protected with
      # `read_only`.
      def insert_image(path, drive: 0, read_only: false)
        image_class = File.extname(path).casecmp?(".d82") ? Storage::D82Image : Storage::D80Image
        insert(Disk.new(image_class.new(path, read_only:)), drive:)
      end

      private

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

      # The disk a BL-D8-DISK module holds (KeyedState).
      def disk_from_fields(input, detached) = Disk.from_fields(input, detached:)

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
