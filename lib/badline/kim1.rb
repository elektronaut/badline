# frozen_string_literal: true

require "badline/kim1/cpu"
require "badline/kim1/rriots"
require "badline/kim1/tape"
require "badline/kim1/panel"
require "badline/kim1/key_entry"
require "badline/kim1/bus"
require "badline/kim1/sound"
require "badline/kim1/teletype"
require "badline/kim1/host_terminal"

module Badline
  # The MOS KIM-1: a 6502 at 1 MHz, 1K of RAM and two 6530 RRIOTs, U2
  # with the monitor in its ROM and U3 with the tape routines (KIM1::Bus).
  # U2's ports drive the keypad and the six LED digits (Panel), and its PB7
  # the audio output (Sound) and the cassette (Tape). Nothing pulls IRQ
  # unless U3's PB7 is wired to it, as the User Manual's appendix H has the
  # user do for U3's timer.
  #
  # RS resets the CPU and both 6530s, and ST pulls NMI, which the monitor
  # leaves to the vector at $17FA: $1C00 there saves the registers and
  # shows the PC. With the SST switch on, every instruction outside the
  # monitor ends in an NMI (CPU#single_step). With the TTY/KB jumper
  # fitted, the monitor talks to a teletype (Teletype) in place of the
  # keypad and display. It runs headless.
  class KIM1
    include Machine::Clocking
    include Machine::Settling
    include KeyEntry

    # The cycle by which the monitor is scanning the display, with a
    # margin.
    BOOT_CYCLES = 10_000

    attr_reader :bus, :cpu, :u2, :u3, :panel, :teletype, :cycles, :init_threshold

    # Whether the SST switch is on.
    attr_accessor :sst

    # Whether U3's PB7, its timer's interrupt, is wired to IRQ.
    attr_accessor :irq_wired

    # The 1 MHz clock. With no video, a frame is nominal: 64 by 260
    # cycles, some 60 a second.
    TIMING = Timing.new(clock_hz: 1_000_000, cycles_per_line: 64, lines_per_frame: 260, crop: [0, 0, 0, 0],
                        pixel_width: 1, dots: 1)

    def family = :kim1

    def portless_board = nil

    def ram = @bus.ram

    # Reads and writes memory as the CPU sees it, through the bus.
    def peek(addr) = @bus.peek(addr)

    def poke(addr, value) = @bus.poke(addr, value)

    # With +tty+ the TTY/KB jumper is fitted, and the monitor talks to a
    # teletype at +baud+ (Teletype::BAUDS) in place of the keypad and
    # display. +ram+ names the RAM, one of Bus::RAM_CONFIGURATIONS, or
    # nil for the stock 1K.
    def initialize(tty: false, baud: 9600, ram: nil)
      @cycles = 0
      @panel = Panel.new(self)
      @panel.tty = tty
      @u2 = MonitorRRIOT.new(rom: ROM.read("kim1/6530-002.rom"), peripheral: @panel)
      @u3 = UserRRIOT.new(rom: ROM.read("kim1/6530-003.rom"))
      @panel.connect(@u2)
      @bus = Bus.new(@u2, @u3, ram: ram || :"1k")
      @cpu = CPU.new(@bus)
      @sst = false
      @irq_wired = false
      @sound = Sound.new(@u2, @u3)
      @teletype = Teletype.new(@panel, baud:)
      @teletype.reset!(0) if tty
      @init_handlers = []
      @init_threshold = BOOT_CYCLES
      @pending_keys = nil
      @key_down = false
      @next_key_at = 0
    end

    # Whether the TTY/KB jumper is fitted.
    def tty? = @panel.tty

    # Fits or takes out the TTY/KB jumper.
    def tty=(fitted)
      @panel.tty = fitted
    end

    def timing = TIMING

    # Types `text` on the teletype with the jumper fitted, and otherwise
    # presses the keys it names (KeyEntry#type_keys).
    def type_text(text)
      return type_keys(text) unless @panel.tty

      @teletype.type(text)
    end

    # What the teletype has printed: #output holds it all.
    def capture_output = @teletype

    # What a front end plays: U2's PB7 or the speaker (Sound), which
    # answers #record and #drain_samples.
    def sound_source = @sound

    # Whether the speaker on U3's PA0 is wired, and plays in place of PB7.
    def speaker? = @sound.speaker

    def speaker=(wired)
      @sound.speaker = wired
    end

    # The machine as the pause menu names it.
    def model_label = "KIM-1, #{ram_kb}K RAM"

    # The RAM in K (Bus#ram_kb).
    def ram_kb = @bus.ram_kb

    # No drive plugs into the KIM-1, and nothing is mounted.
    def true_drive = nil

    def mounted? = false

    def mounted_path = ""

    # The 6530s count ahead of the CPU. With SST on, the board pulls NMI
    # ahead of an opcode fetch outside the monitor.
    def cycle!
      handle_init if @cycles == @init_threshold
      feed_keys unless @pending_keys.nil?

      @u2.cycle!
      @u3.cycle!
      @sound.cycle! if @sound.recording?
      @teletype.cycle!(@cycles, @u2.port_b_output.anybits?(0x01) && @teletype.line_high?) if @panel.tty
      @cpu.irq = @irq_wired && @u3.irq?
      @cpu.single_step if @sst
      @cpu.cycle!

      @cycles += 1
    end

    # RS: the RST line resets the CPU and both 6530s. RAM keeps what it
    # holds. A teletype then sends RUBOUT for the monitor to time.
    def reset!
      @u2.reset!
      @u3.reset!
      @cpu.reset!
      @teletype.reset!(@cycles) if @panel.tty
    end

    alias press_reset reset!

    # Switches the machine off and on: RAM starts cleared, and RS resets
    # everything else.
    def power_cycle!
      @bus.power_on!
      reset!
    end

    # ST: an edge on NMI.
    def press_stop
      @cpu.nmi = true
    end

    # Holds down the key Panel::KEYS names `name`.
    def press_key(name)
      @panel.press(name)
    end

    def release_key
      @panel.release
    end

    # The segments each LED digit shows (Panel#display).
    def display = @panel.display

    # The display as text, such as "0200 A9" (Panel#display_text).
    def display_text = @panel.display_text

    # The cassette deck on U2's PB7.
    def tape = @panel.tape
  end
end

require "badline/snapshot/kim1_setup"
require "badline/kim1/keyed_state"
require "badline/kim1/keyed_modules"
