# frozen_string_literal: true

require "badline/drives/model8050"
require "badline/drives/model9060/sasi_target"
require "badline/drives/model9060/sasi_bus"
require "badline/drives/model9060/parts"
require "badline/drives/model9060/idle"
require "badline/drives/model9060/keyed_state"

module Badline
  module Drives
    # The D9060 hard disk of the PET and CBM-II, one 5 MB drive on an
    # IEEE-488 unit (technical manual PN 990441; DOS board 300010).
    #
    # The DOS board is the 8050's with the floppy half given over to a SASI
    # host. The interface processor (IP) runs DOS 3.0 from 16 KB of ROM at
    # $C000, with the 8050's two 6532s on the IEEE-488 bus (Model8050's
    # IPBus and IEEEPort). The SASI host, a second 6502 in the floppy
    # controller's place, runs 300515 from 2 KB at $F800, with a 6810 for
    # its zero page and stack and a VIA facing the hard disk's controller
    # (SASIBus, SASILines, SASITarget). The two meet in the 8050's 4 KB of
    # common RAM, where the IP leaves jobs and the host turns each into a
    # SASI command.
    #
    # Reset starts both. The host waits on the common RAM for the IP, which
    # tests it and answers, and the DOS settles into its idle loop with the
    # host polling the job queue.
    #
    # The interface processor's side of the board and the clocking against
    # the host are the 8050's (Model8050::DOSBoard), and the unit sleeps
    # through both processors' idle loops (Idle).
    #
    # N runs as the DOS runs it, but for the six passes that write and
    # read back test patterns over every block, an hour of the hardware's
    # time: once Format Unit has erased the disk, the IP goes from the first
    # pass straight on to where they end, as if every block had passed.
    # The DOS then writes the bad-block list, the BAM, the header and the
    # directory as c1541 formats a .d90, byte for byte.
    class Model9060
      include Model8050::DOSBoard
      include Idle

      CLOCK_HZ = 1_000_000

      # The host cycles by which a unit switched on with the machine has
      # run its RAM tests and the host's start-up, and reads its jumpers.
      BOOT_CYCLES = 1_500_000

      # DOS 3.0's format: the first of its pattern passes (FORMAT_PASSES),
      # where the pass number ($2D) is 0, and the code after the last
      # (FORMAT_DONE), with the pass number at 6.
      FORMAT_PASSES = 0xcb02
      FORMAT_DONE = 0xcc15
      PASS = 0x2d

      def sasi_cpu = settled(@sasi_cpu)

      def sasi_bus = settled(@sasi_bus)

      def target = settled(@target)

      def model_name = "9060"

      # The heads the drive has, which J14 tells the DOS.
      def heads = 4

      def boot_cycles = BOOT_CYCLES

      # Whether the unit is where VICE saves it: both processors between
      # instructions, the host at the start of its job loop.
      def settled_for_vice?
        host = sasi_cpu
        ip_cpu.boundary? && host.boundary? && host.program_counter == Idle::SASI_LOOP
      end

      # +dos_rom+ covers $C000-$FFFF and +sasi_rom+ $F800-$FFFF of the
      # host's, each defaulting to the image in the ROM path. +device+ is
      # the number the jumpers set, 8 to 15. Only the default DOS has its
      # pattern passes skipped.
      def initialize(dos_rom: nil, sasi_rom: nil, host_clock_hz: CLOCK_HZ, device: 8)
        @device = device
        @host_clock_hz = host_clock_hz
        @phase = 0
        @cycles = 0
        @format_trap = dos_rom.nil?
        build_ip(dos_rom || ROM.load("9060/dos-3.0.rom", 0xc000))
        build_sasi(sasi_rom || ROM.read("9060/sasi-300515-revb.rom"))
        @ip_cpu = Model8050::IPCPU.new(@ip_bus)
        @ip_cpu.power_on!
        @sasi_cpu = SASICPU.new(@sasi_bus)
        @sasi_cpu.power_on!
        init_idle
        @ieee_bus.attach(self)
      end

      # Whether the activity LED is lit: of the LEDs, bit 1 is the
      # activity LED and bit 2 the status LED.
      def led_on? = leds.anybits?(0x02)

      # Puts the Storage::D90Image in the drive. Nil takes it out.
      def insert(image)
        settle!
        @target.disk = image
      end

      # Puts in the .d90 image at +path+, write-protected with `read_only`.
      # An image of neither drive's size takes this drive's heads.
      def insert_image(path, read_only: false)
        image_heads = Storage::D90Image.heads_for(File.size(path)) || heads
        insert(Storage::D90Image.new(path, read_only:, heads: image_heads))
      end

      # The image in the drive, or nil.
      def disk = @target.disk

      # Writes reach the image as each Write ends, so there is nothing to
      # store.
      def flush = nil

      # The bus's IFC line resets both processors and every chip. RAM keeps
      # its contents, and the hard disk's controller runs on.
      def reset!
        settle!
        @data_riot.reset!
        @control_riot.reset!
        @via.reset!
        @ip_cpu.reset!
        @sasi_cpu.reset!
      end

      def inspect
        "#<#{self.class.name} cycles=#{@cycles} ip=(#{@ip_cpu.inspect}) sasi=(#{@sasi_cpu.inspect})>"
      end

      private

      def run_cycle
        step
        skip_format_passes if @format_trap && @target.fast?
        watch_loops if @idle_skip
      end

      def build_ip(rom)
        @common = Memory.new([], length: 0x1000)
        @ieee_bus = IEEEBus.new
        @ieee_port = Model8050::IEEEPort.new(device: @device, bus: @ieee_bus)
        @data_riot = Model8050::DataRIOT.new(peripheral: Model8050::DataLines.new(@ieee_port))
        @control_riot = Model8050::ControlRIOT.new(peripheral: Model8050::ControlLines.new(@ieee_port))
        @ieee_port.data_riot = @data_riot
        @ieee_port.control_riot = @control_riot
        @ip_bus = Model8050::IPBus.new(rom:, common: @common, data_riot: @data_riot, control_riot: @control_riot)
      end

      def build_sasi(rom)
        @target = SASITarget.new
        @lines = SASILines.new(@target, four_heads: heads == 4)
        @via = SASIVIA.new(start: 0x0080, peripheral: @lines)
        @lines.via = @via
        @sasi_bus = SASIBus.new(rom: ROM.new(rom, length: rom.length), common: @common, via: @via)
      end

      # One cycle of the board: the controller and the chips, then the IP
      # and the host, each in its own half of the cycle. ATN reaches UE1's
      # PA7 as the port latched it. UE1 pulls the IP's IRQ and the VIA the
      # host's.
      def step
        @control_riot.pa7 = @ieee_port.atn_low?
        @data_riot.cycle!
        @control_riot.cycle!
        @via.cycle!
        @lines.cycle!
        @ip_cpu.irq = @control_riot.irq?
        @ip_cpu.cycle!
        @sasi_cpu.irq = @via.irq?
        @sasi_cpu.cycle!
        @cycles += 1
      end

      # Sends the IP from the first pattern pass on to the end of the last.
      def skip_format_passes
        ip = @ip_cpu
        return unless ip.program_counter == FORMAT_PASSES && ip.boundary? && @ip_bus.peek(PASS).zero?

        @ip_bus.poke(PASS, 6)
        ip.program_counter = FORMAT_DONE
      end
    end

    # The D9090: the D9060's board on a six-head drive, 7.5 MB, with J14
    # telling the DOS so.
    class Model9090 < Model9060
      def model_name = "9090"

      def heads = 6
    end
  end
end
