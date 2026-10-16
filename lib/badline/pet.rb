# frozen_string_literal: true

require "badline/pet/model"
require "badline/pet/cpu"
require "badline/pet/via"
require "badline/pet/via_ports"
require "badline/pet/keyboard_ports"
require "badline/pet/characters"
require "badline/pet/canvas"
require "badline/pet/discrete_video"
require "badline/pet/bus"

module Badline
  # The Commodore PET and CBM: a 6502 at 1 MHz, two 6520 PIAs at $E810 and
  # $E820, a 6522 VIA at $E840 and, from the 4032 on, a 6545 CRTC at
  # $E880. Every chip's IRQ is wired to the CPU's, and nothing pulls NMI.
  # Nothing halts the CPU either: the video reads the screen RAM between
  # its accesses.
  #
  # The video's vertical drive line, low in the retrace, reaches PIA 1's
  # CB1, whose falling edge is the editor's 50 or 60 Hz interrupt, and the
  # VIA's PB5. The discrete boards count it out themselves
  # (DiscreteVideo), and the CRTC boards take it from the CRTC's vertical
  # sync, inverted.
  #
  # The key matrix hangs off PIA 1 (KeyboardPorts), the graphics one or
  # the business one as the model has, and type_text types through the
  # editor's keyboard buffer.
  #
  # The discrete boards paint their picture (DiscreteVideo) on a Canvas.
  # It runs headless, with no CRTC picture, sound or media yet.
  class PET
    include Machine::KeyboardBuffer
    include Machine::Clocking

    attr_reader :model, :bus, :cpu, :pia1, :pia2, :via, :crtc, :keyboard, :cycles, :init_threshold

    # The editor's frame rate: 50 or 60 on a CRTC board, 60 on the others.
    attr_reader :refresh_hz

    def ram = @bus.ram

    # Reads and writes memory as the CPU sees it, through the bus.
    def peek(addr) = @bus.peek(addr)

    def poke(addr, value) = @bus.poke(addr, value)

    def install_debug_register(&) = @bus.install_debug_register(&)

    def family = :pet

    # +model+ names one of Model::ALL, with +ram_kb+ of RAM below $8000
    # (Model::RAM_SIZES) in place of the model's own when not nil. A CRTC
    # model runs its 50 Hz editor, or its 60 Hz one for +refresh_hz+ 60.
    def initialize(model: Model::DEFAULT, ram_kb: nil, refresh_hz: 50, debug: false)
      @model = Model.named(model)
      ram_kb ||= @model.ram_kb
      raise ArgumentError, "a PET has no #{ram_kb}K RAM board" unless Model::RAM_SIZES.include?(ram_kb)

      @refresh_hz = @model.crtc? ? refresh_hz : 60
      @crtc_video = @model.crtc?
      @crtc = Chips::CRTC.new
      @vertical_drive = true
      matrix = @model.keyboard == :business ? KeyboardPorts::BUSINESS_MATRIX : KeyboardPorts::GRAPHICS_MATRIX
      @keyboard = Input::Keyboard.new(matrix:)
      keyboard_ports = KeyboardPorts.new(@keyboard)
      @pia1 = Chips::PIA.new(peripheral: keyboard_ports)
      keyboard_ports.connect(@pia1)
      @pia2 = Chips::PIA.new
      @via = VIA.new(start: 0xe800, peripheral: VIAPorts.new(self))
      @bus = Bus.new(model: @model, ram_kb:, editor: @model.editor(@refresh_hz), pia1: @pia1, pia2: @pia2,
                     via: @via, crtc: @crtc)
      @discrete = DiscreteVideo.new(@bus.screen.cells, Characters.new(@model.characters), @via)
      @canvas = @discrete.canvas
      @canvas = Canvas.new(@model.video == :crtc80 ? 704 : 384, 273) if @crtc_video
      @cpu = CPU.new(@bus, debug:)
      @cycles = 0
      @init_handlers = []
      @pending_keys = nil
      @init_threshold = boot_cycles(ram_kb)
    end

    # The vertical drive line, high but in the retrace.
    def vertical_drive? = @vertical_drive

    # The Canvas a front end shows.
    def video = @canvas

    # The 1 MHz clock and the frame the editor sets up, and all of the
    # Canvas. The CRTC editors' lines are 50 cycles, 400 of them a frame at
    # 50 Hz and 333 at 60 Hz, which a program can change. 80 columns show
    # two dots to a window pixel.
    def timing
      crop = [0, 0, @canvas.width, @canvas.height]
      if @crtc_video
        Timing.new(clock_hz: 1_000_000, cycles_per_line: 50, lines_per_frame: @refresh_hz == 50 ? 400 : 333,
                   crop:, pixel_width: 1, dots: @model.video == :crtc80 ? 2 : 1)
      else
        Timing.new(clock_hz: 1_000_000, cycles_per_line: DiscreteVideo::CYCLES_PER_LINE,
                   lines_per_frame: DiscreteVideo::LINES_PER_FRAME, crop:, pixel_width: 1, dots: 1)
      end
    end

    # The video counts and moves the vertical drive line, then the PIAs
    # and the VIA clock, ahead of the CPU.
    def cycle!
      handle_init if @cycles == @init_threshold
      feed_keyboard if @pending_keys

      if @crtc_video
        @crtc.cycle!
        drive_retrace(!@crtc.vsync?)
      else
        @discrete.cycle!
        drive_retrace(@discrete.vertical_drive?)
      end
      @pia1.cycle!
      @pia2.cycle!
      @via.cycle!
      @cpu.irq = @pia1.irq? || @pia2.irq? || @via.irq?
      @cpu.cycle!

      @cycles += 1
    end

    # The RES line reaches the CPU, the PIAs, the VIA, the CRTC and the
    # 8096's control register.
    def reset!
      @pia1.reset!
      @pia2.reset!
      @via.reset!
      @crtc.reset!
      @bus.reset!
      @cpu.reset!
    end

    # Switches the machine off and on: RAM starts cleared, and the RES
    # line resets everything else.
    def power_cycle!
      @bus.power_on!
      reset!
    end

    # Where the editor keeps its keyboard buffer: in page 2 under BASIC 1,
    # in the zero page and page 2 under BASIC 2 and 4.
    def keyboard_buffer
      @model.basic1? ? Machine::KeyboardBuffer::PET_BASIC1_LAYOUT : Machine::KeyboardBuffer::PET_LAYOUT
    end

    private

    # The cycle by which the KERNAL has booted and BASIC printed READY,
    # with a margin. The RAM test takes most of it, about 41,000 to
    # 44,000 cycles a K, and the CRTC editors take another 600,000 or so
    # before it: READY is up by about 440,000 on a 2001 with 8K, 1,450,000
    # on a 3032 and 1,980,000 on an 8032.
    def boot_cycles(ram_kb) = (@model.basic == "pet/basic4.rom" ? 700_000 : 150_000) + (46_000 * ram_kb)

    def drive_retrace(high)
      return if high == @vertical_drive

      @vertical_drive = high
      @pia1.cb1 = high
    end
  end
end
