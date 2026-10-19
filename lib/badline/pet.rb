# frozen_string_literal: true

require "badline/pet/rom_sets"
require "badline/pet/model"
require "badline/pet/cpu"
require "badline/pet/via"
require "badline/pet/via_ports"
require "badline/pet/keyboard_ports"
require "badline/pet/ieee_ports"
require "badline/pet/ieee_traps"
require "badline/pet/ieee_drive"
require "badline/pet/cassettes"
require "badline/pet/characters"
require "badline/pet/canvas"
require "badline/pet/discrete_video"
require "badline/pet/crtc_video"
require "badline/pet/bus"
require "badline/pet/sound"
require "badline/snapshot/pet_setup"
require "badline/pet/keyed_parts"
require "badline/pet/keyed_state"
require "badline/pet/keyed_modules"

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
  # The CRTC boards paint theirs from the CRTC's outputs (CRTCVideo).
  # The VIA's CB2 is the sound (Sound).
  #
  # Device 8 answers through traps on the KERNAL's IEEE-488 primitives
  # (IEEETraps), on the IEEE-488 bus (IEEEPorts), or a true 2031 on the
  # bus answers (IEEEDrive), and each cassette port has a datasette
  # (Cassettes). It runs headless.
  class PET
    include Machine::KeyboardBuffer
    include Machine::Clocking
    include Machine::Settling
    include IEEETraps
    include IEEEDrive

    attr_reader :model, :bus, :cpu, :pia1, :pia2, :via, :crtc, :keyboard, :ieee, :cassettes, :cycles, :init_threshold

    # The editor's frame rate: 50 or 60 on a CRTC board, 60 on the others.
    attr_reader :refresh_hz

    # The RAM below $8000, in K.
    attr_reader :ram_kb

    # The 8296's board jumpers that are fitted, by name.
    attr_reader :jumpers

    def ram = @bus.ram

    # Reads and writes memory as the CPU sees it, through the bus.
    def peek(addr) = @bus.peek(addr)

    def poke(addr, value) = @bus.poke(addr, value)

    def install_debug_register(&) = @bus.install_debug_register(&)

    def family = :pet

    # The datasette on cassette port #1, where a tape goes in (Cassettes).
    def datasette = @cassettes.datasette1

    # +model+ names one of Model::ALL, with +ram_kb+ of RAM below $8000
    # (Model::RAM_SIZES) in place of the model's own when not nil. A CRTC
    # model runs its 50 Hz editor, or its 60 Hz one for +refresh_hz+ 60.
    # +basic+, +editor+ and +characters+ name ROMs the board takes in place
    # of its own (Model.upgraded, Model.fitted), and +jumpers+ the 8296's
    # board jumpers (ROMSets::JUMPERS). +true_drive_model+ names the drive
    # plug_true_drive plugs in (Drives::IEEEModels).
    def initialize(model: Model::DEFAULT, ram_kb: nil, refresh_hz: 50, debug: false, basic: nil, editor: nil,
                   characters: nil, jumpers: [], true_drive_model: Drives::IEEEModels::DEFAULT)
      @model = Model.fitted(Model.upgraded(Model.named(model), basic, editor), characters)
      raise ArgumentError, "the SuperPET is built as PET::SuperPET" if @model.superpet? && !superpet?

      ram_kb ||= @model.ram_kb
      raise ArgumentError, "the #{@model.name} has no #{ram_kb}K RAM board" unless Model.ram_fits?(@model, ram_kb)

      @ram_kb = ram_kb
      @jumpers = Model.checked_jumpers(@model, jumpers)

      @refresh_hz = @model.crtc? ? refresh_hz : 60
      @crtc_video = @model.crtc?
      @vertical_drive = true
      matrix = @model.keyboard == :business ? KeyboardPorts::BUSINESS_MATRIX : KeyboardPorts::GRAPHICS_MATRIX
      @keyboard = Input::Keyboard.new(matrix:)
      keyboard_ports = KeyboardPorts.new(@keyboard)
      @keyboard_ports = keyboard_ports
      registers = Array.new(Chips::CRTC::MASKS.length, 0)
      @pia1 = Chips::PIA.new(peripheral: keyboard_ports)
      @ieee = IEEEPorts.new(Drives::IEEEBus.new)
      @pia2 = Chips::PIA.new(peripheral: @ieee)
      @via = VIA.new(start: 0xe800, peripheral: VIAPorts.new(self))
      @sound = Sound.new(@via)
      @cassettes = Cassettes.new(@pia1, @via)
      watch_tapes
      keyboard_ports.connect(@pia1, @ieee, @cassettes)
      characters = Characters.new(@model.characters)
      @crtc_output = CRTCVideo.new(characters, @via, registers, columns80: @model.video == :crtc80,
                                                                board8296: @model.cbm8296?)
      @crtc = Chips::CRTC.new(@crtc_output, registers:)
      @ieee.connect(@pia1, @pia2, @via)
      @bus = Bus.new(model: @model, ram_kb:, editor: @model.editor(@refresh_hz), pia1: @pia1, pia2: @pia2,
                     via: @via, crtc: @crtc, jumpers: @jumpers)
      @crtc_output.cells = @bus.screen.cells
      @discrete = DiscreteVideo.new(@bus.screen.cells, characters, @via)
      @canvas = @crtc_video ? @crtc_output.canvas : @discrete.canvas
      cassettes = @cassettes
      ieee = @ieee
      @bus.on_io_write do
        cassettes.lines_written
        ieee.lines_written
      end
      @cpu = CPU.new(@bus, debug:)
      @cycles = 0
      @init_handlers = []
      @pending_keys = nil
      @init_keys = nil
      @dos = nil
      @ieee_trap = nil
      @capture_output = nil
      init_ieee_drives(true_drive_model)
      @init_threshold = boot_cycles(ram_kb)
    end

    # Whether this is the SuperPET's board (SuperPET).
    def superpet? = false

    # Whether the picture shows the SuperPET's APL characters.
    def apl_characters? = false

    # Whether an autostart finds BASIC to type into.
    def boots_basic? = true

    # The vertical drive line, high but in the retrace.
    def vertical_drive? = @vertical_drive

    # The model, its RAM and its editor's frame rate as the pause menu
    # names them, such as "8032, 32K RAM, 50 HZ", all 128K on an 8296.
    def model_label = "#{@model.name.upcase}, #{@model.cbm8296? ? 128 : @ram_kb}K RAM, #{@refresh_hz} HZ"

    # The Canvas a front end shows.
    def video = @canvas

    # The 1 MHz clock and the frame the editor sets up, and all of the
    # Canvas. The CRTC editors' lines and frames are their ROM's
    # (ROMSets.crtc_frame), which a program can change. 80 columns show
    # two dots to a window pixel.
    def timing
      crop = [0, 0, @canvas.width, @canvas.height]
      if @crtc_video
        cycles_per_line, lines_per_frame = ROMSets.crtc_frame(@model.editor(@refresh_hz), @refresh_hz)
        Timing.new(clock_hz: 1_000_000, cycles_per_line:, lines_per_frame:,
                   crop:, pixel_width: 1, dots: @model.video == :crtc80 ? 2 : 1)
      else
        Timing.new(clock_hz: 1_000_000, cycles_per_line: DiscreteVideo::CYCLES_PER_LINE,
                   lines_per_frame: DiscreteVideo::LINES_PER_FRAME, crop:, pixel_width: 1, dots: 1)
      end
    end

    # The video counts and moves the vertical drive line, then the PIAs
    # and the VIA clock, ahead of the CPU, and the drive after it.
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
      @sound.cycle! if @sound.recording?
      @cassettes.cycle! if @tapes_running
      @cpu.irq = @pia1.irq? || @pia2.irq? || @via.irq?
      @cpu.cycle!
      clock_ieee_drives

      @cycles += 1
    end

    # What a front end plays: the VIA's CB2 (Sound), which answers #record
    # and #drain_samples.
    def sound_source = @sound

    # The RES line reaches the CPU, the PIAs, the VIA, the CRTC, the
    # 8096's control register and, as IFC, the drive.
    def reset!
      @pia1.reset!
      @pia2.reset!
      @via.reset!
      @crtc.reset!
      @bus.reset!
      reset_ieee_drives
      @ieee.lines_written
      @cpu.reset!
    end

    # Switches the machine off and on: RAM starts cleared, and the RES
    # line resets everything else.
    def power_cycle!
      @bus.power_on!
      reset!
    end

    # Puts a program file's bytes where its first two say, through the bus,
    # and returns that address.
    def load_prg(data)
      load_addr = data[0] | (data[1] << 8)
      bytes = data[2..] || []
      bytes = bytes[0, 0x10000 - load_addr] if load_addr + bytes.length > 0x10000
      bytes.each_with_index { |byte, i| @bus.poke(load_addr + i, byte) }
      load_addr
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

    # The decks are clocked only while a tape runs.
    def watch_tapes
      @tapes_running = false
      @cassettes.on_running_change { tapes_changed }
    end

    def tapes_changed
      @tapes_running = @cassettes.running?
    end

    def drive_retrace(high)
      return if high == @vertical_drive

      @vertical_drive = high
      @pia1.cb1 = high
    end
  end
end

require "badline/pet/superpet"
