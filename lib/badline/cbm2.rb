# frozen_string_literal: true

require "badline/chips/acia"
require "badline/chips/tpi"
require "badline/cbm2/model"
require "badline/cbm2/p500/model"
require "badline/cbm2/bus"
require "badline/cbm2/cpu"
require "badline/cbm2/acia"
require "badline/cbm2/keyboard_ports"
require "badline/cbm2/crtc_video"
require "badline/cbm2/sid_page"
require "badline/cbm2/ieee_layout"
require "badline/cbm2/ieee_traps"
require "badline/cbm2/ieee_ports"
require "badline/cbm2/ieee_drive"
require "badline/snapshot/cbm2_setup"
require "badline/cbm2/keyed_state"
require "badline/cbm2/keyed_modules"
require "badline/cbm2/p500"

module Badline
  # The Commodore CBM-II's B series, the 610, 620, 710 and 720: a 6509 at
  # 2 MHz on a bus of sixteen 64K segments (Bus, CPU), a 6845 CRTC at
  # $D800, a 6581 SID at $DA00, a 6526 CIA at $DC00, a 6551 ACIA at $DD00
  # and two 6525 TPIs at $DE00 and $DF00. Nothing halts the CPU: the video
  # reads its own screen RAM between the CPU's accesses.
  #
  # TPI1 is the interrupt controller, and its IRQ the CPU's only one. Its
  # inputs are the mains on I0, the IEEE-488 bus's SRQ on I1, the CIA on
  # I2, the coprocessor board on I3 and the ACIA on I4, each pulled low to
  # interrupt. The mains, 50 or 60 Hz, is the system tick, and feeds the
  # CIA's TOD pin too. TPI2 scans the key matrix and reads the model's
  # jumpers (KeyboardPorts), and type_text types through the editor's
  # keyboard buffer in segment 15.
  #
  # The DRAM's refresh takes the CPU's clock away for a cycle (Refresh),
  # every 20 cycles or so: about 4.5% of its time.
  #
  # The CRTC paints its picture from the screen RAM and the character ROM
  # (CRTCVideo). Device 8 answers through traps on the KERNAL's IEEE-488
  # primitives (IEEETraps), or a true 2031, 8050 or 8250 on the bus
  # (IEEEPorts, IEEEDrive) answers. It runs headless.
  class CBM2
    include Machine::KeyboardBuffer
    include Machine::Clocking
    include Machine::Settling
    include IEEETraps
    include IEEEDrive

    CLOCK_HZ = 2_000_000

    # The DRAM refresh (sheet 3 of schematic 8256043, U89 and U55): a
    # counter of the CPU's cycles asks for a refresh once it reaches 20,
    # stops there, and the refresh comes on the next opcode fetch (SYNC),
    # which it holds off a cycle with RDY while it stops the CPU's clock,
    # and clears the counter.
    REFRESH_COUNT = 20

    # The segment BASIC keeps its program text in.
    TEXT_SEGMENT = 1

    # The editor's keyboard buffer in segment 15, KEYD at $03AB and NDX at
    # $D1, the same in 901244-03b and -04a.
    KEYBOARD_LAYOUT = Machine::KeyboardBuffer::Layout.new(address: 0x03ab, count: 0xd1, capacity: 10)

    attr_reader :model, :bus, :cpu, :crtc, :sid, :cia, :acia, :tpi1, :tpi2, :keyboard, :ieee, :mains_hz, :kernal,
                :cycles, :init_threshold

    def ram = @bus.ram

    # Whether the DRAM refresh takes its cycles from the CPU.
    def refresh? = @refreshing

    def family = :cbm2

    # Reads and writes memory as the CPU sees it, in its execution segment.
    def peek(addr) = @bus.peek(addr)

    def poke(addr, value) = @bus.poke(addr, value)

    def install_debug_register(&) = @bus.install_debug_register(&)

    def keyboard_buffer = KEYBOARD_LAYOUT

    def sound_source = @sid

    # The Canvas a front end shows (CRTCVideo).
    def video = @video.canvas

    # What paints the picture.
    def crtc_video = @video

    # +model+ names one of Model::ALL, +kernal+ one of Model::KERNALS, and
    # +mains_hz+ the mains, 50 or 60, which also sets a 600's jumper for
    # the editor's 60 Hz CRTC table. +refresh+ false leaves out the DRAM
    # refresh's stolen cycles.
    def initialize(model: Model::DEFAULT, kernal: "04a", mains_hz: 50, refresh: true, debug: false)
      @model = Model.named(model)
      raise ArgumentError, "no CBM-II KERNAL named #{kernal}" unless Model::KERNALS.key?(kernal)
      raise ArgumentError, "the mains is 50 or 60 Hz, not #{mains_hz}" unless [50, 60].include?(mains_hz)

      @kernal = kernal
      @mains_hz = mains_hz
      @bus = Bus.new(basic: Model.basic(@model, kernal), kernal: Model::KERNALS.fetch(kernal),
                     ram_segments: @model.ram_segments)
      @ieee = IEEEPorts.new(Drives::IEEEBus.new)
      @tpi1 = Chips::TPI.new(peripheral: @ieee)
      registers = Array.new(Chips::CRTC::MASKS.length, 0)
      @video = CRTCVideo.new(ROM.read(@model.characters), @bus.screen, @tpi1, registers,
                             high_profile: @model.high_profile)
      @crtc = Chips::CRTC.new(@video, registers:)
      @sid = Chips::SID.new(model: :mos6581, at: 0xda00)
      @cia = Chips::CIA.new(start: 0xdc00, peripheral: @ieee.data, region: Region::PAL.with(clock_hz: CLOCK_HZ),
                            tod_hz: mains_hz)
      @ieee.connect(@cia, @tpi1)
      @acia = ACIA.new(self, CLOCK_HZ)
      @keyboard = Input::Keyboard.new(matrix: KeyboardPorts::MATRIX)
      keyboard_ports = KeyboardPorts.new(@keyboard, jumpers)
      @tpi2 = Chips::TPI.new(peripheral: keyboard_ports)
      keyboard_ports.connect(@tpi2)
      map_io
      @cpu = CPU.new(@bus, debug:)
      @cycles = 0
      @mains_half_period = CLOCK_HZ / (2 * mains_hz)
      @mains_countdown = @mains_half_period
      @mains_high = true
      @refresh = 0
      @refreshing = refresh
      @acia_irq = false
      @acia_due = Chips::ACIA::NEVER
      @init_handlers = []
      @pending_keys = nil
      @dos = nil
      @ieee_trap = nil
      @capture_output = nil
      init_ieee_drives
      @init_threshold = boot_cycles
    end

    # The model, its RAM and its mains as the pause menu names them, such
    # as "610, 128K RAM, 50 HZ".
    def model_label = "#{@model.name}, #{@model.ram_kb}K RAM, #{@mains_hz} HZ"

    # The 2 MHz clock and the frame of the editor's CRTC table, nominal,
    # since a program can program the CRTC otherwise, and all of the
    # Canvas, two dots to a window pixel.
    def timing
      cycles_per_line, lines_per_frame = crtc_frame
      canvas = @video.canvas
      Timing.new(clock_hz: CLOCK_HZ, cycles_per_line:, lines_per_frame:, crop: [0, 0, canvas.width, canvas.height],
                 pixel_width: 1, dots: 2)
    end

    # The CRTC and the mains ahead of the chips, then TPI1's inputs from
    # the CIA and the ACIA, and the CPU last.
    def cycle!
      handle_init if @cycles == @init_threshold
      feed_keyboard if @pending_keys

      @crtc.cycle!
      tick_mains
      @cia.cycle!
      @sid.cycle!
      @acia.run!(@cycles) if @cycles >= @acia_due
      tpi1 = @tpi1
      tpi1.interrupt_line(2, !@cia.interrupted?)
      tpi1.interrupt_line(4, !@acia_irq)
      @cpu.irq = tpi1.irq?
      if @refreshing && @refresh >= REFRESH_COUNT && @cpu.boundary?
        @refresh = 0
        @cpu.stall!
      else
        @refresh += 1 if @refresh < REFRESH_COUNT
        @cpu.cycle!
      end
      clock_ieee_drives

      @cycles += 1
    end

    # The ACIA's IRQ line, and the cycle it next has something to do at.
    def acia_changed(irq, due)
      @acia_irq = irq
      @acia_due = due
    end

    # The RES line reaches the CPU and its segment registers, the CRTC, the
    # SID, the CIA, the ACIA and both TPIs.
    def reset!
      @crtc.reset!
      @sid.reset!
      @cia.reset!
      @acia.reset!
      @tpi1.reset!
      @tpi2.reset!
      @bus.reset!
      @cpu.reset!
      reset_ieee_drives
    end

    # Puts a program file's bytes where its first two say in BASIC's text
    # segment, segment 1, and returns that address.
    def load_prg(data)
      load_addr = data[0] | (data[1] << 8)
      bytes = data[2..] || []
      bytes = bytes[0, 0x10000 - load_addr] if load_addr + bytes.length > 0x10000
      bytes.each_with_index { |byte, i| @bus.poke_bank(TEXT_SEGMENT, load_addr + i, byte) }
      load_addr
    end

    # Puts a cartridge's ROM chips in (Bus#attach_cartridge) and switches
    # the machine off and on, for the KERNAL to find it as it starts.
    def attach_cartridge(chips)
      @bus.attach_cartridge(chips)
      power_cycle!
    end

    # Switches the machine off and on: RAM starts cleared, and the RES
    # line resets everything else.
    def power_cycle!
      @bus.power_on!
      reset!
    end

    private

    # PC6 and PC7 as the board's jumpers drive them.
    def jumpers
      return 0x80 if @model.high_profile

      @mains_hz == 60 ? 0x40 : 0x00
    end

    def map_io
      @bus.map_io(0xd8, @crtc)
      @bus.map_io(0xda, SIDPage.new(@sid))
      @bus.map_io(0xdc, @cia)
      @bus.map_io(0xdd, @acia)
      @bus.map_io(0xde, @tpi1)
      @bus.map_io(0xdf, @tpi2)
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

    # The characters a line and the lines a frame of the editor's table:
    # the 700's, or the 600's 50 or 60 Hz one.
    def crtc_frame
      return [108, 367] if @model.high_profile

      @mains_hz == 60 ? [127, 262] : [128, 313]
    end

    # The cycle by which the KERNAL has tested the RAM board, about 3.7
    # million cycles a segment with the refresh, and BASIC printed READY, with a margin.
    def boot_cycles = 1_000_000 + (3_800_000 * @model.ram_segments.length)
  end
end
