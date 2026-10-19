# frozen_string_literal: true

require "badline/kim1/cpu"
require "badline/kim1/rriots"
require "badline/kim1/panel"
require "badline/kim1/key_entry"
require "badline/kim1/bus"

module Badline
  # The MOS KIM-1: a 6502 at 1 MHz, 1K of RAM and two 6530 RRIOTs, U2
  # with the monitor in its ROM and U3 with the tape routines (KIM1::Bus).
  # U2's ports drive the keypad and the six LED digits (Panel). Nothing
  # pulls IRQ, and neither 6530's timer reaches it.
  #
  # RS resets the CPU and both 6530s, and ST pulls NMI, which the monitor
  # leaves to the vector at $17FA: $1C00 there saves the registers and
  # shows the PC. With the SST switch on, every instruction outside the
  # monitor ends in an NMI (CPU#single_step). It runs headless.
  class KIM1
    include Machine::Clocking
    include KeyEntry

    # The cycle by which the monitor is scanning the display, with a
    # margin.
    BOOT_CYCLES = 10_000

    attr_reader :bus, :cpu, :u2, :u3, :panel, :cycles, :init_threshold

    # Whether the SST switch is on.
    attr_accessor :sst

    def family = :kim1

    def ram = @bus.ram

    # Reads and writes memory as the CPU sees it, through the bus.
    def peek(addr) = @bus.peek(addr)

    def poke(addr, value) = @bus.poke(addr, value)

    # With +tty+ the TTY/KB jumper is fitted, and the monitor talks to a
    # teletype in place of the keypad and display.
    def initialize(tty: false)
      @cycles = 0
      @panel = Panel.new(self)
      @panel.tty = tty
      @u2 = MonitorRRIOT.new(rom: ROM.read("kim1/6530-002.rom"), peripheral: @panel)
      @u3 = UserRRIOT.new(rom: ROM.read("kim1/6530-003.rom"))
      @panel.connect(@u2)
      @bus = Bus.new(@u2, @u3)
      @cpu = CPU.new(@bus)
      @sst = false
      @init_handlers = []
      @init_threshold = BOOT_CYCLES
      @pending_keys = nil
      @key_down = false
      @next_key_at = 0
    end

    # Whether the TTY/KB jumper is fitted.
    def tty? = @panel.tty

    # The 6530s count ahead of the CPU. With SST on, the board pulls NMI
    # ahead of an opcode fetch outside the monitor.
    def cycle!
      handle_init if @cycles == @init_threshold
      feed_keys unless @pending_keys.nil?

      @u2.cycle!
      @u3.cycle!
      @cpu.single_step if @sst
      @cpu.cycle!

      @cycles += 1
    end

    # RS: the RST line resets the CPU and both 6530s. RAM keeps what it
    # holds.
    def reset!
      @u2.reset!
      @u3.reset!
      @cpu.reset!
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
  end
end
