# frozen_string_literal: true

require "badline/drives/model8050"
require "badline/drives/model4040/ip_bus"
require "badline/drives/model4040/parts"
require "badline/drives/model4040/disk"
require "badline/drives/model4040/mechanism"
require "badline/drives/model4040/keyed_state"

module Badline
  module Drives
    # The 4040 dual disk drive of the PET and CBM-II, two Shugart SA390
    # drives on one IEEE-488 unit (schematic 320806, the 8050's parent).
    #
    # The board is the 8050's (Model8050::Board) with an older floppy side.
    # A 16 MHz crystal clocks both processors at 1 MHz on opposite phases.
    # The interface processor runs DOS 2.1 from 12 KB of ROM at $D000, with
    # the 8050's 6532s on the bus and the same common RAM, on a bus that
    # doesn't decode A15 (IPBus). The floppy controller is a 6504, with no
    # SO pin, on the 8050's map (Model8050::FDCBus): it runs the program in
    # its 6530 (901466-04) and polls the VIA for byte ready, whose own
    # interrupt line goes nowhere, so only the 6530's timer interrupts it
    # (Mechanism). The disks are the 1541's, 35 tracks of 17 to 21
    # sectors, a .d64 each (Disk).
    #
    # At reset the controller waits for the common RAM's $0400 to read 0,
    # starts, and writes its timer's period there. The interface processor
    # tests its RAM and ROMs, has the controller reset its drives, and
    # bumps both heads to track 1.
    class Model4040
      include Model8050::Board
      include Model8050::Idle
      include Model8050::KeyedState

      CLOCK_HZ = Model8050::CLOCK_HZ

      # The host cycles by which a unit switched on with the machine has
      # run the IP's tests and bumped both heads, and reads its jumpers.
      BOOT_CYCLES = 2_500_000

      # Where DOS 2.1's idle loop and the controller's job loop start over
      # (Model8050::Idle).
      IP_LOOP = 0xd4b7
      FDC_LOOP = 0xfc54

      def model_name = "4040"

      def boot_cycles = BOOT_CYCLES

      def sides = 1

      # +dos_rom+ covers $D000-$FFFF and +fdc_rom+ is the 6530's mask, each
      # defaulting to the image in the ROM path: the revised DOS 2.1 that
      # xpet's 4040 runs, and 901466-04. +device+ is the number the jumpers
      # set, 8 to 15.
      def initialize(dos_rom: nil, fdc_rom: nil, host_clock_hz: CLOCK_HZ, device: 8)
        @device = device
        @host_clock_hz = host_clock_hz
        @phase = 0
        @cycles = 0
        build_ip(dos_rom || ROM.load(dos_file, dos_start))
        build_fdc(fdc_rom || ROM.read(fdc_file))
        @ip_cpu = IPCPU.new(@ip_bus)
        @fdc_cpu = FDCCPU.new(@fdc_bus)
        init_idle(ip_loop, fdc_loop)
        @ieee_bus.attach(self)
      end

      # Puts in the .d64 image at +path+, or the DOS 1 disk a .d67 holds,
      # write-protected with `read_only`.
      def insert_image(path, drive: 0, read_only: false)
        image = if File.extname(path).casecmp?(".d67")
                  Storage::D67Image.new(path, read_only:)
                else
                  Storage::D64Image.new(path, read_only:)
                end
        insert(Disk.new(image), drive:)
      end

      private

      def dos_file = "4040/dos-2.1-rev.rom"

      def dos_start = 0xd000

      def fdc_file = "4040/fdc-901466-04.rom"

      def ip_loop = IP_LOOP

      def fdc_loop = FDC_LOOP

      def build_ip(rom)
        @common = Memory.new([], length: 0x1000)
        @ieee_bus = IEEEBus.new
        @ieee_port = Model8050::IEEEPort.new(device: @device, bus: @ieee_bus)
        @data_riot = Model8050::DataRIOT.new(peripheral: Model8050::DataLines.new(@ieee_port))
        @control_riot = Model8050::ControlRIOT.new(peripheral: Model8050::ControlLines.new(@ieee_port))
        @ieee_port.data_riot = @data_riot
        @ieee_port.control_riot = @control_riot
        @ip_bus = IPBus.new(rom:, common: @common, data_riot: @data_riot, control_riot: @control_riot)
      end

      def build_fdc(rom)
        @mechanism = Mechanism.new
        @via = Model8050::ControllerVIA.new(start: 0x0040, peripheral: ReadLines.new(@mechanism))
        @rriot = Model8050::ControllerRRIOT.new(rom:, peripheral: StatusLines.new(@mechanism))
        @fdc_bus = Model8050::FDCBus.new(common: @common, via: @via, rriot: @rriot)
        @mechanism.via = @via
        @mechanism.rriot = @rriot
      end

      # The disk a BL-D8-DISK module holds (Model8050::KeyedState).
      def disk_from_fields(input, detached) = Disk.from_fields(input, detached:)

      # One cycle of the board: the drives, then the chips, then the IP and
      # the FDC, each in its own half of the cycle, as on the 8050. Only the
      # 6530 pulls the FDC's IRQ, and the FDC finds byte ready by polling.
      def step
        @mechanism.cycle!
        @control_riot.pa7 = @ieee_port.atn_low?
        @data_riot.cycle!
        @control_riot.cycle!
        @via.cycle!
        @rriot.cycle!
        @ip_cpu.irq = @control_riot.irq?
        @ip_cpu.cycle!
        @fdc_cpu.irq = @rriot.irq?
        @fdc_cpu.cycle!
        @cycles += 1
      end
    end

    # The 3040: the 4040's board with the first DOS 2.1, as xpet's 3040
    # runs it, 901468-11 to -13.
    class Model3040 < Model4040
      # Where the first DOS 2.1's idle loop starts over.
      IP_LOOP = 0xd4b8

      def model_name = "3040"

      private

      def dos_file = "4040/dos-2.1.rom"

      def ip_loop = IP_LOOP
    end

    # The 2040: the 4040's board with DOS 1.2 in the sockets at $E000 and
    # $F000, UJ1 at $D000 left empty, and 901466-02 in the controller's
    # 6530, as the 3040 with DOS 1 has it too. Its disks are DOS 1's .d67,
    # with 20 sectors on tracks 18 to 24 (Storage::D67Image). The
    # controller starts at once, with no handshake on the common RAM, and
    # the interface processor leaves the common RAM alone at boot.
    class Model2040 < Model4040
      # Where DOS 1.2's idle loop and its controller's job loop start over.
      IP_LOOP = 0xe27e
      FDC_LOOP = 0xfc47

      def model_name = "2040"

      # Puts in the .d67 image at +path+, write-protected with `read_only`.
      def insert_image(path, drive: 0, read_only: false)
        insert(Disk.new(Storage::D67Image.new(path, read_only:)), drive:)
      end

      private

      def dos_file = "4040/dos-1.2.rom"

      def dos_start = 0xe000

      def fdc_file = "4040/fdc-901466-02.rom"

      def ip_loop = IP_LOOP

      def fdc_loop = FDC_LOOP
    end
  end
end
