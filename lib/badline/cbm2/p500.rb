# frozen_string_literal: true

require "badline/cbm2/p500/model"
require "badline/cbm2/p500/pages"
require "badline/cbm2/p500/control_ports"
require "badline/cbm2/p500/ieee_layout"
require "badline/cbm2/p500/keyed_state"

module Badline
  class CBM2
    # The P500, the CBM 510: the B series' 6509, SID, CIA, ACIA and TPIs on
    # the same segment bus (Bus, CPU), at the VIC-II's clock of about
    # 1 MHz, with a VIC-II at $D800 in place of the 6845. RAM fills segments
    # 0 and 1.
    #
    # Segment 15 holds what the B series' does but for $C000-$D7FF: the
    # character ROM at $C000, which the CPU reads too, the 1K static video
    # matrix at $D000 and the colour RAM's nibbles at $D400. What the VIC
    # reads follows the P500's video bus (Chips::VIC::Bank#map_video_bus):
    # TPI1's CA is STATVID and its CB VICDOTSEL, and TPI2's PC6 and PC7
    # drive VA14 and VA15, which pick the 16K of segment 0 the VIC sees.
    # BA halts the CPU as on the C64, and the VIC's IRQ reaches the CPU
    # along with TPI1's.
    #
    # TPI1 is the interrupt controller as on the B series, with the mains
    # on I0, the CIA on I2 and the ACIA on I4. TPI2 scans the B series'
    # key matrix (KeyboardPorts), and the CIA reads the two control ports
    # (ControlPorts). Device 8 answers through traps on the KERNAL's
    # IEEE-488 primitives as on the B series (IEEETraps, with the P500's
    # IEEELayout), or a true 2031, 8050 or 8250 on the bus answers, on the
    # same ports as the B series' (IEEEPorts, IEEEDrive).
    class P500
      include Machine::KeyboardBuffer
      include Machine::Clocking
      include Machine::Settling
      include IEEETraps
      include IEEEDrive

      # The segment BASIC keeps its program text in.
      TEXT_SEGMENT = 0

      # The ACIA at $DD00, whose IRQ reaches TPI1's I4.
      class ACIA < Chips::ACIA
      end

      attr_reader :model, :bus, :cpu, :vic, :sid, :cia, :acia, :tpi1, :tpi2, :keyboard, :joystick1, :joystick2,
                  :color_ram, :ieee, :mains_hz, :kernal, :cycles, :init_threshold

      def ram = @bus.ram

      # The VIC refreshes the DRAM in its own half of the cycle, so the
      # refresh takes none of the CPU's.
      def refresh? = false

      def family = :cbm2

      def peek(addr) = @bus.peek(addr)

      def poke(addr, value) = @bus.poke(addr, value)

      def install_debug_register(&) = @bus.install_debug_register(&)

      def keyboard_buffer = CBM2::KEYBOARD_LAYOUT

      def sound_source = @sid

      # The VIC, whose display a front end shows.
      def video = @vic

      def region = @model.region

      # +model+ names one of Model::ALL, and +mains_hz+ the mains, 50 or
      # 60, the model's region's unless given.
      def initialize(model: Model::DEFAULT, mains_hz: nil, debug: false)
        @model = Model.named(model)
        @mains_hz = mains_hz || @model.region.mains_hz
        raise ArgumentError, "the mains is 50 or 60 Hz, not #{@mains_hz}" unless [50, 60].include?(@mains_hz)

        @kernal = Model::KERNALS.keys.first
        clock_hz = @model.region.clock_hz
        @bus = Bus.new(basic: Model::BASIC, kernal: Model::KERNALS.fetch(@kernal), ram_segments: Model::RAM_SEGMENTS,
                       screen_length: 0x400)
        @vic = Chips::VIC.new(model: :mos6569, region: @model.region)
        @color_ram = C64::ColorMemory.new(@vic, start: 0xd400)
        map_video
        @ieee = IEEEPorts.new(Drives::IEEEBus.new)
        @tpi1 = Chips::TPI.new(peripheral: @ieee)
        @sid = Chips::SID.new(model: :mos6581, at: 0xda00)
        @joystick1 = Input::Joystick.new
        @joystick2 = Input::Joystick.new
        @cia = Chips::CIA.new(start: 0xdc00, peripheral: ControlPorts.new(@joystick1, @joystick2, @ieee.data),
                              region: @model.region, tod_hz: @mains_hz)
        @ieee.connect(@cia, @tpi1)
        @acia = ACIA.new(self, clock_hz)
        @keyboard = Input::Keyboard.new(matrix: KeyboardPorts::MATRIX)
        keyboard_ports = KeyboardPorts.new(@keyboard, 0xc0)
        @tpi2 = Chips::TPI.new(peripheral: keyboard_ports)
        keyboard_ports.connect(@tpi2)
        map_io
        @cpu = CPU.new(@bus, debug:)
        @cycles = 0
        @mains_half_period = clock_hz / (2 * @mains_hz)
        @mains_countdown = @mains_half_period
        @mains_high = true
        # The B series' refresh counter, which CBM2::KeyedState saves: 0
        # here, where the VIC refreshes the DRAM.
        @refresh = 0
        @acia_irq = false
        @acia_due = Chips::ACIA::NEVER
        @init_handlers = []
        @pending_keys = nil
        @dos = nil
        @ieee_trap = nil
        @capture_output = nil
        init_ieee_drives
        @init_threshold = INIT_THRESHOLD
        update_video_bus
      end

      # The model, its RAM and its mains as the pause menu names them, such
      # as "510, 128K RAM, 50 HZ".
      def model_label = "#{@model.name}, #{@model.ram_kb}K RAM, #{@mains_hz} HZ"

      def timing
        region = @model.region
        Timing.new(clock_hz: region.clock_hz, cycles_per_line: region.cycles_per_line,
                   lines_per_frame: region.lines_per_frame, crop: region.crop, pixel_width: 1, dots: 1)
      end

      # The VIC and the mains ahead of the chips, then TPI1's inputs from
      # the CIA and the ACIA, and the CPU last, halted while BA is low on a
      # read.
      def cycle!
        handle_init if @cycles == @init_threshold
        feed_keyboard if @pending_keys

        vic = @vic
        vic.cycle!
        tick_mains
        @cia.cycle!
        @sid.cycle!
        @acia.run!(@cycles) if @cycles >= @acia_due
        tpi1 = @tpi1
        tpi1.interrupt_line(2, !@cia.interrupted?)
        tpi1.interrupt_line(4, !@acia_irq)
        cpu = @cpu
        cpu.irq = tpi1.irq? || vic.interrupted?
        cpu.pending_write? || !vic.ba_low? ? cpu.cycle! : cpu.stall!
        clock_ieee_drives

        @cycles += 1
      end

      # The ACIA's IRQ line, and the cycle it next has something to do at.
      def acia_changed(irq, due)
        @acia_irq = irq
        @acia_due = due
      end

      # STATVID and VICDOTSEL from TPI1's CA and CB, PC6 and PC7 in mode 0,
      # and VA14 and VA15 from TPI2's PC6 and PC7, to the VIC's bank.
      def update_video_bus
        lines = @tpi1.port_c_output
        @vic.vic_bank.video_bus_lines(lines.anybits?(0x40), lines.anybits?(0x80), @tpi2.port_c_output >> 6)
      end

      # The RES line reaches the CPU and its segment registers, the SID, the
      # CIA, the ACIA and both TPIs. The VIC has no reset pin.
      def reset!
        @sid.reset!
        @cia.reset!
        @acia.reset!
        @tpi1.reset!
        @tpi2.reset!
        update_video_bus
        @bus.reset!
        @cpu.reset!
        reset_ieee_drives
      end

      # Puts a program file's bytes where its first two say in BASIC's text
      # segment, segment 0, and returns that address.
      def load_prg(data)
        load_addr = data[0] | (data[1] << 8)
        bytes = data[2..] || []
        bytes = bytes[0, 0x10000 - load_addr] if load_addr + bytes.length > 0x10000
        bytes.each_with_index { |byte, i| @bus.poke_bank(TEXT_SEGMENT, load_addr + i, byte) }
        load_addr
      end

      # The IEEELayout of 901234-02.
      def trap_layout = IEEELayout::LAYOUT

      # Puts a cartridge's ROM chips in (Bus#attach_cartridge) and switches
      # the machine off and on, for the KERNAL to find it as it starts.
      def attach_cartridge(chips)
        @bus.attach_cartridge(chips)
        power_cycle!
      end

      # Switches the machine off and on: RAM starts cleared, the VIC starts
      # over, and the RES line resets everything else.
      def power_cycle!
        @bus.power_on!
        @color_ram.clear!
        @vic.power_on!
        reset!
      end

      # The cycle by which the KERNAL has tested segments 0 and 1 and BASIC
      # printed READY, with a margin.
      INIT_THRESHOLD = 8_600_000

      private

      # The character ROM at $C000 and the colour RAM at $D400 of segment
      # 15, and what the VIC reads.
      def map_video
        character_rom = ROM.load("character.rom", 0xc000)
        @bus.map_video(character_rom, 0xc0, 0x10)
        @bus.map_video(ColorPages.new(@color_ram), 0xd4, 0x04, writable: true)
        bank = @vic.vic_bank
        bank.map_character_rom(character_rom, base: 0xc000)
        bank.map_video_bus(@bus.segment_ram[0], @bus.screen, @color_ram, 0xd400)
      end

      def map_io
        @bus.map_io(0xd8, VICPage.new(@vic))
        @bus.map_io(0xda, SIDPage.new(@sid))
        @bus.map_io(0xdc, @cia)
        @bus.map_io(0xdd, @acia)
        @bus.map_io(0xde, TPIPage.new(@tpi1, self))
        @bus.map_io(0xdf, TPIPage.new(@tpi2, self))
      end

      # The mains, low for half its period and high for the other half, on
      # TPI1's I0, whose falling edge latches the tick.
      def tick_mains
        @mains_countdown -= 1
        return unless @mains_countdown.zero?

        @mains_countdown = @mains_half_period
        @mains_high = !@mains_high
        @tpi1.interrupt_line(0, @mains_high)
      end
    end
  end
end
