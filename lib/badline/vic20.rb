# frozen_string_literal: true

require "badline/vic20/bus"
require "badline/vic20/cpu"
require "badline/vic20/vic"

module Badline
  # The Commodore VIC-20 with the PAL 6561: a 6502 at the VIC's clock, the
  # VIC-I and two 6522 VIAs. VIA 1, at $9110, pulls NMI, and VIA 2, at
  # $9120, pulls IRQ. Nothing else interrupts the CPU, and nothing halts
  # it: the VIC fetches in the half of the cycle the CPU leaves alone.
  #
  # So far it runs headless, with nothing plugged into the VIAs' ports: no
  # keyboard, joystick, tape or serial bus.
  class Vic20
    include IntegerHelper
    include KeyboardBuffer

    attr_reader :bus, :cpu, :vic, :via1, :via2, :cycles, :init_threshold

    def ram = @bus.ram

    # The chip whose #display a front end shows.
    def video = @vic

    # The clock, the raster and the crop of the VIC's region.
    def timing
      region = @vic.region
      Timing.new(clock_hz: region.clock_hz, cycles_per_line: region.cycles_per_line,
                 lines_per_frame: region.lines_per_frame, crop: region.crop)
    end

    # +ram+ names the RAM expansion, one of Bus::RAM_CONFIGURATIONS.
    def initialize(ram: :unexpanded, debug: false)
      @vic = VIC.new
      @via1 = VIA.new(start: 0x9000)
      @via2 = VIA.new(start: 0x9000)
      @bus = Bus.new(vic: @vic, via1: @via1, via2: @via2, blocks: Bus::RAM_CONFIGURATIONS.fetch(ram))
      @vic.connect(@bus)
      @cpu = CPU.new(@bus, debug:)
      @cycles = 0
      @nmi_asserted = false
      @init_handlers = []
      @pending_keys = nil
      @init_threshold = boot_cycles
    end

    # The VIC and the VIAs clock ahead of the CPU, as the C64's chips do,
    # so a register write lands on the cycle after the one it was issued
    # on.
    def cycle!
      handle_init if @cycles == @init_threshold
      feed_keyboard if @pending_keys

      @vic.cycle!
      @via1.cycle!
      @via2.cycle!
      @cpu.irq = @via2.irq?
      drive_nmi
      @cpu.cycle!

      @cycles += 1
    end

    # Runs `count` cycles, one #cycle! after another.
    def run_cycles(count)
      i = 0
      while i < count
        cycle!
        i += 1
      end
    end

    # Runs cycles until the block returns true or the cycle count passes
    # `limit`, checking before each cycle.
    def run_until(limit)
      cycle! until yield || @cycles > limit
    end

    # Runs the block once the KERNAL has booted (see init_threshold), or
    # now if it has.
    def on_init(&block)
      if @cycles < @init_threshold
        @init_handlers << block
      else
        block.call
      end
    end

    # Calls the block with the exit code a VICE testprog writes to $910F.
    def install_debug_register(&) = @bus.install_debug_register(&)

    # Writes a PRG's bytes to RAM at its load address, and returns that.
    def load_prg(data)
      uint16(data[0], data[1]).tap do |load_addr|
        ram.write(load_addr, data[2..])
      end
    end

    # The RES line reaches the CPU and both VIAs. The VIC has no reset pin.
    def reset!
      @via1.reset!
      @via2.reset!
      @nmi_asserted = false
      @cpu.reset!
    end

    # Switches the machine off and on: RAM and the VIC start from their
    # power-on state, and the RES line resets everything else.
    def power_cycle!
      @bus.power_on!
      @vic.power_on!
      reset!
    end

    def inspect
      "#<#{self.class.name} cycles=#{@cycles} cpu=(#{@cpu.inspect})>"
    end

    private

    # The cycle by which the KERNAL has booted and BASIC printed READY,
    # with a margin. The KERNAL's RAM test takes most of it, and runs up
    # from $1000 until it finds no RAM, so each 8K block on from BLK1
    # adds about 615,000 cycles. Unexpanded, READY is up by about 557,000.
    def boot_cycles
      tested = 0
      tested += 1 while tested < 3 && @bus.ram?(%i[blk1 blk2 blk3][tested])
      700_000 + (650_000 * tested)
    end

    # VIA 1's IRQ output drives NMI, and the CPU takes an interrupt on its
    # falling edge.
    def drive_nmi
      nmi = @via1.irq?
      @cpu.nmi = true if nmi && !@nmi_asserted
      @nmi_asserted = nmi
    end

    def handle_init
      @init_handlers.each(&:call)
    end
  end
end
